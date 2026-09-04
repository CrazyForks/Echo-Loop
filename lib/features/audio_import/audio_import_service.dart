import 'dart:async';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:universal_io/io.dart';

import '../../models/audio_item.dart';
import '../../providers/audio_library_provider.dart';
import '../../providers/collection_provider.dart';
import '../../services/app_logger.dart';
import '../../services/reliable_http_downloader.dart';
import '../../utils/app_data_dir.dart';
import '../../utils/audio_duration.dart';
import 'audio_finalization_service.dart';
import 'audio_import_models.dart';
import 'audio_registration_service.dart';
import 'audio_transcode_service.dart';

typedef AudioImportProgressCallback =
    void Function(int receivedBytes, int? totalBytes);

/// 链接音频导入服务。
///
/// 负责把外部音频直链下载到应用沙盒并创建普通 [AudioItem]。未来 RSS 解析只需
/// 把单集 enclosure 规整成直链来源，即可复用本服务。
class AudioImportService {
  static const _logTag = 'AudioImport';

  AudioImportService({
    Dio? dio,
    Uuid? uuid,
    Future<Directory> Function()? resolveDataDir,
    Future<String> Function(String absolutePath)? computeSha256,
    Future<int> Function(String relativePath)? readDurationSeconds,
    AudioRegistrationService? registrationService,
    AudioTranscodeService? transcodeService,
  }) : _dio = dio ?? Dio(),
       _uuid = uuid ?? const Uuid(),
       _resolveDataDir = resolveDataDir ?? getAppDataDirectory,
       _readDurationSeconds = readDurationSeconds ?? getAudioDurationSeconds,
       _registrationService =
           registrationService ?? AudioRegistrationService(uuid: uuid),
       _finalizationService = AudioFinalizationService(
         transcodeService: transcodeService ?? AudioTranscodeService(),
         computeSha256: computeSha256,
         uuid: uuid,
       ) {
    _downloader = DioReliableHttpDownloader(dio: _dio);
  }

  final Dio _dio;

  /// `ReliableHttpDownloader` 接口本身不提供释放能力，本类也不做 `dispose`
  /// （复用调用方注入的 [_dio] 或全局默认 Dio，生命周期不归本类管）。
  late final ReliableHttpDownloader _downloader;
  final Uuid _uuid;
  final Future<Directory> Function() _resolveDataDir;
  final Future<int> Function(String relativePath) _readDurationSeconds;
  final AudioRegistrationService _registrationService;
  final AudioFinalizationService _finalizationService;

  static const supportedExtensions = {'mp3', 'wav', 'm4a', 'aac', 'flac'};

  Future<AudioItem> importFromUrl({
    required String url,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
    AudioImportProgressCallback? onProgress,
  }) async {
    final resolved = await resolveUrl(url, cancelToken: cancelToken);
    final dataDir = await _resolveDataDir();
    final audioId = _uuid.v4();
    final downloadedPath = await _downloadToTemp(
      resolved: resolved,
      audioId: audioId,
      dataDir: dataDir,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
    final finalizedAudio = await _finalizeDownloadedAudio(
      dataDir: dataDir,
      tempRelativePath: downloadedPath,
    );

    final result = await _registrationService.registerSandboxedAudio(
      input: SandboxedAudioRegistrationInput(
        name: resolved.displayName,
        relativePath: finalizedAudio.relativePath,
        importSourceType: AudioImportSourceType.directUrl,
        importSourceUrl: resolved.uri.toString(),
        audioSha256: finalizedAudio.sha256,
        originalAudioSha256: finalizedAudio.originalSha256,
      ),
      audioLibrary: audioLibrary,
      audioLibraryState: audioLibraryState,
      collectionList: collectionList,
      collectionState: collectionState,
      collectionId: collectionId,
    );

    switch (result) {
      case AudioRegistrationAdded(:final item):
        if (finalizedAudio.created &&
            item.audioPath != finalizedAudio.relativePath) {
          await _deleteIfExists(
            File(p.join(dataDir.path, finalizedAudio.relativePath)),
          );
        }
        return item;
      case AudioRegistrationDuplicate(:final name):
        if (finalizedAudio.created) {
          await _deleteIfExists(
            File(p.join(dataDir.path, finalizedAudio.relativePath)),
          );
        }
        throw AudioImportException(
          AudioImportFailureCode.duplicate,
          'Audio already exists: $name',
        );
    }
  }

  /// 下载 podcast 单集 enclosure 到沙盒，仅落盘并返回文件信息，**不创建 [AudioItem]**。
  ///
  /// 与 [importFromUrl] 的区别：跳过严格的直链 MIME/音频校验（podcast enclosure
  /// 常返回 `application/octet-stream` 或经重定向域名分发），扩展名按
  /// URL 后缀 → enclosureType → `mp3` 兜底确定。调用方拿到结果后自行更新已存在的
  /// 占位条目（保留 podcast 元字段），避免在资源库产生重复孤儿条目。
  Future<DownloadedAudio> downloadEpisodeToSandbox({
    required String url,
    String? enclosureType,
    CancelToken? cancelToken,
    AudioImportProgressCallback? onProgress,
  }) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AudioImportException(
        AudioImportFailureCode.invalidUrl,
        'Invalid audio URL',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const AudioImportException(
        AudioImportFailureCode.unsupportedScheme,
        'Only http and https URLs are supported',
      );
    }

    final normalizedUri = _normalizePodcastAudioUri(uri);
    final extension =
        _extensionFromUri(normalizedUri) ??
        _extensionFromMimeType(enclosureType) ??
        'mp3';
    final safeBaseName = _safeFileBaseName(
      _baseNameFromUri(normalizedUri, extension),
    );

    final dataDir = await _resolveDataDir();
    final audioId = _uuid.v4();
    final downloadedPath = await _downloadToTemp(
      resolved: ResolvedAudioImport(
        uri: normalizedUri,
        displayName: safeBaseName,
        fileName: '$safeBaseName.$extension',
        extension: extension,
      ),
      audioId: audioId,
      dataDir: dataDir,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
    final finalizedAudio = await _finalizeDownloadedAudio(
      dataDir: dataDir,
      tempRelativePath: downloadedPath,
    );

    final duration = await _tryReadDuration(finalizedAudio.relativePath);
    return DownloadedAudio(
      relativePath: finalizedAudio.relativePath,
      durationSeconds: duration,
      created: finalizedAudio.created,
      audioSha256: finalizedAudio.sha256,
      originalAudioSha256: finalizedAudio.originalSha256,
    );
  }

  /// 丢弃尚未写入 AudioItem 的下载结果，只删除本次新建的文件。
  Future<void> discardDownloadedAudio(DownloadedAudio downloaded) async {
    if (!downloaded.created) return;
    final dataDir = await _resolveDataDir();
    await _deleteIfExists(File(p.join(dataDir.path, downloaded.relativePath)));
  }

  Future<ResolvedAudioImport> resolveUrl(
    String input, {
    CancelToken? cancelToken,
  }) async {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AudioImportException(
        AudioImportFailureCode.invalidUrl,
        'Invalid audio URL',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const AudioImportException(
        AudioImportFailureCode.unsupportedScheme,
        'Only http and https URLs are supported',
      );
    }

    String? mimeType;
    int? contentLength;
    try {
      final response = await _dio.head<Object>(
        trimmed,
        options: Options(followRedirects: true, validateStatus: (_) => true),
        cancelToken: cancelToken,
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 400) {
        mimeType = response.headers.value(Headers.contentTypeHeader);
        contentLength = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        );
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const AudioImportException(
          AudioImportFailureCode.canceled,
          'Audio import canceled',
        );
      }
      // 部分服务器禁用 HEAD；后续 GET 下载时再失败。
    }

    final extFromUrl = _extensionFromUri(uri);
    final extFromMime = _extensionFromMimeType(mimeType);
    final extension = extFromUrl ?? extFromMime;
    final isAudioMime = mimeType == null || mimeType.startsWith('audio/');

    if (extension == null) {
      if (!isAudioMime) {
        throw AudioImportException(
          AudioImportFailureCode.notAudio,
          'URL does not point to an audio file',
        );
      }
      throw const AudioImportException(
        AudioImportFailureCode.unsupportedFormat,
        'Unsupported audio format',
      );
    }
    if (!supportedExtensions.contains(extension)) {
      throw AudioImportException(
        AudioImportFailureCode.unsupportedFormat,
        'Unsupported audio format: .$extension',
      );
    }
    if (!isAudioMime) {
      throw AudioImportException(
        AudioImportFailureCode.notAudio,
        'URL does not point to an audio file',
      );
    }

    final baseName = _baseNameFromUri(uri, extension);
    final safeBaseName = _safeFileBaseName(baseName);
    return ResolvedAudioImport(
      uri: uri,
      displayName: safeBaseName,
      fileName: '$safeBaseName.$extension',
      extension: extension,
      mimeType: mimeType,
      contentLength: contentLength,
    );
  }

  Future<String> _downloadToTemp({
    required ResolvedAudioImport resolved,
    required String audioId,
    required Directory dataDir,
    required CancelToken? cancelToken,
    required AudioImportProgressCallback? onProgress,
  }) async {
    final tmpDir = Directory(p.join(dataDir.path, 'tmp', 'audio_import'));
    await tmpDir.create(recursive: true);

    final downloadedFile = File(
      p.join(tmpDir.path, '$audioId.${resolved.extension}'),
    );
    try {
      // allowResume: false——导入取消/失败不需要跨调用续传，失败即清理
      // `.part`，与迁移前手写 finally 删临时文件的既有语义一致。
      await _downloader.download(
        uri: resolved.uri,
        savePath: downloadedFile.path,
        allowResume: false,
        cancelToken: cancelToken,
        onProgress: (received, total) => onProgress?.call(received, total),
      );
      return p.join('tmp', 'audio_import', p.basename(downloadedFile.path));
    } on ReliableDownloadException catch (e) {
      if (e.kind == ReliableDownloadFailure.cancelled) {
        throw const AudioImportException(
          AudioImportFailureCode.canceled,
          'Audio import canceled',
        );
      }
      _logDownloadFailure(resolved.uri, e);
      // 磁盘写入失败已被下载器内部归类为 storage（如空间不足），单独区分，
      // 不与「网络请求失败」混为一谈。
      if (e.kind == ReliableDownloadFailure.storage) {
        throw AudioImportException(
          AudioImportFailureCode.storage,
          'Failed to save audio',
          e,
        );
      }
      throw AudioImportException(
        AudioImportFailureCode.network,
        'Failed to download audio',
        e,
      );
    } on FileSystemException catch (e) {
      throw AudioImportException(
        AudioImportFailureCode.storage,
        'Failed to save audio',
        e,
      );
    }
  }

  Future<FinalizedAudio> _finalizeDownloadedAudio({
    required Directory dataDir,
    required String tempRelativePath,
  }) {
    return _finalizationService.finalize(
      dataDir: dataDir,
      tempRelativePath: tempRelativePath,
      targetSubdir: p.join('audios', 'imported'),
    );
  }

  Future<int> _tryReadDuration(String relativePath) async {
    try {
      return await _readDurationSeconds(relativePath);
    } catch (_) {
      return 0;
    }
  }

  String? _extensionFromUri(Uri uri) {
    final ext = p.extension(uri.path).replaceFirst('.', '').toLowerCase();
    if (ext.isEmpty) return null;
    return ext;
  }

  /// BBC RSS 历史数据常落库为 HTTP enclosure，而同一 feed 同时提供 HTTPS 版本。
  /// 下载前在这里做最小兜底，避免 Android cleartext 策略或中间网络拦截 HTTP。
  Uri _normalizePodcastAudioUri(Uri uri) {
    if (uri.scheme != 'http' || uri.host != 'open.live.bbc.co.uk') {
      return uri;
    }
    final segments = uri.pathSegments;
    final protoIndex = segments.indexOf('proto');
    if (protoIndex == -1 || protoIndex + 1 >= segments.length) {
      return uri.replace(scheme: 'https');
    }
    final nextSegments = List<String>.from(segments);
    if (nextSegments[protoIndex + 1] == 'http') {
      nextSegments[protoIndex + 1] = 'https';
    }
    return uri.replace(scheme: 'https', pathSegments: nextSegments);
  }

  void _logDownloadFailure(Uri uri, ReliableDownloadException error) {
    AppLogger.log(
      _logTag,
      'download failed url=$uri '
      'kind=${error.kind} '
      'status=${error.statusCode ?? "(null)"} '
      'message=${error.message} '
      'cause=${error.cause ?? "(null)"}',
    );
  }

  String? _extensionFromMimeType(String? mimeType) {
    if (mimeType == null) return null;
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    return switch (normalized) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/wav' || 'audio/x-wav' => 'wav',
      'audio/mp4' || 'audio/x-m4a' => 'm4a',
      'audio/aac' => 'aac',
      'audio/flac' || 'audio/x-flac' => 'flac',
      _ => null,
    };
  }

  String _baseNameFromUri(Uri uri, String extension) {
    final lastSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final decoded = Uri.decodeComponent(lastSegment);
    final withoutExt = p.basenameWithoutExtension(decoded);
    if (withoutExt.trim().isNotEmpty) return withoutExt.trim();
    return 'audio-$extension';
  }

  String _safeFileBaseName(String input) {
    final replaced = input
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (replaced.isEmpty) return 'audio';
    return replaced.length > 80 ? replaced.substring(0, 80).trim() : replaced;
  }

  Future<void> _deleteIfExists(File file) async {
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {}
  }
}
