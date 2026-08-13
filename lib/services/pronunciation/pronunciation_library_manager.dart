import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../app_logger.dart';
import '../reliable_http_downloader.dart';
import 'pronunciation_repository.dart';

const pronunciationLibraryUrl =
    'https://cdn.echo-loop.top/dictionary/pronunciation-v1.zip';
const pronunciationLibrarySha256 =
    'e96d1f26575b8568b5215f413dbffa952c4d7fada9e17df2810f038959cd09b5';
const pronunciationLibraryVersion = 'v1';

const _pendingInstallFileName = '_pending_install.json';
const _downloadPhase = 'downloading';
const _installPhase = 'installing';
const _replacePhase = 'replacing';

class PronunciationLibraryPaths {
  const PronunciationLibraryPaths({
    required this.database,
    required this.audioDirectory,
  });
  final String database;
  final String audioDirectory;
}

/// 发音资源包下载、校验与安装管理器。
class PronunciationLibraryManager {
  PronunciationLibraryManager({
    Dio? dio,
    String url = pronunciationLibraryUrl,
    String sha256 = pronunciationLibrarySha256,
  }) : _dio = dio ?? Dio(),
       _ownsDio = dio == null,
       _url = url,
       _sha256 = sha256 {
    _downloader = DioReliableHttpDownloader(dio: _dio);
  }

  @visibleForTesting
  PronunciationLibraryManager.withDownloader(
    ReliableHttpDownloader downloader, {
    String url = pronunciationLibraryUrl,
    String sha256 = pronunciationLibrarySha256,
  }) : _dio = Dio(),
       _ownsDio = true,
       _downloader = downloader,
       _url = url,
       _sha256 = sha256;

  final Dio _dio;
  final bool _ownsDio;
  late final ReliableHttpDownloader _downloader;
  final String _url;
  final String _sha256;

  Future<String> _root() async =>
      p.join((await getApplicationSupportDirectory()).path, 'pronunciation');
  Future<String> _versionDir() async =>
      p.join(await _root(), pronunciationLibraryVersion);

  Future<File> _pendingInstallFile() async =>
      File(p.join(await _root(), _pendingInstallFileName));

  /// 返回是否有被进程终止的下载或安装事务需要在下次启动时继续。
  Future<bool> hasPendingInstall() async =>
      (await _pendingInstallFile()).existsSync();

  /// 清理安全可判定的安装残留，并恢复替换阶段被中断时的旧版本。
  ///
  /// 下载阶段保留归档和 `.part`，交由可靠下载器在后续任务中继续；解压目录
  /// 不可安全复用，始终从完整归档重新生成。
  Future<void> recoverInterruptedInstall() async {
    final root = await _root();
    if (!Directory(root).existsSync()) return;
    final pending = await _pendingInstallFile();
    final phase = await _readPendingPhase(pending);
    final target = Directory(await _versionDir());
    final previous = Directory('${target.path}.previous');
    final staging = Directory(
      p.join(root, '_staging_$pronunciationLibraryVersion'),
    );

    if (staging.existsSync()) await staging.delete(recursive: true);

    if (phase == _replacePhase) {
      if (await _validatedPathsForDirectory(target) != null) {
        if (previous.existsSync()) await previous.delete(recursive: true);
        await _deleteIfExists(pending);
        await _deleteDownloadArtifacts(root);
        return;
      }
      if (await _validatedPathsForDirectory(previous) != null) {
        if (target.existsSync()) await target.delete(recursive: true);
        await previous.rename(target.path);
      }
      return;
    }

    // 无事务时的 previous 是已完成替换后的历史遗留；有效目标优先。
    if (phase == null && previous.existsSync()) {
      if (await _validatedPathsForDirectory(target) != null) {
        await previous.delete(recursive: true);
      } else if (!target.existsSync() &&
          await _validatedPathsForDirectory(previous) != null) {
        await previous.rename(target.path);
      } else {
        await previous.delete(recursive: true);
      }
    }
    if (phase == null) await _deleteDownloadArtifacts(root);
  }

  Future<PronunciationLibraryPaths?> installedPaths() async {
    return _validatedPathsForDirectory(Directory(await _versionDir()));
  }

  Future<PronunciationLibraryPaths?> _validatedPathsForDirectory(
    Directory dir,
  ) async {
    final marker = File(p.join(dir.path, 'install.json'));
    final database = File(p.join(dir.path, 'pronunciation.sqlite'));
    final audio = Directory(p.join(dir.path, 'audio'));
    if (!marker.existsSync() || !database.existsSync() || !audio.existsSync()) {
      return null;
    }
    try {
      final data =
          jsonDecode(await marker.readAsString()) as Map<String, Object?>;
      if (data['version'] != pronunciationLibraryVersion ||
          data['sha256'] != _sha256) {
        return null;
      }
      validatePronunciationDatabase(database.path);
      return PronunciationLibraryPaths(
        database: database.path,
        audioDirectory: audio.path,
      );
    } catch (error) {
      AppLogger.log(
        'Pronunciation',
        'installed library validation failed: $error',
      );
      return null;
    }
  }

  Future<int> localSizeBytes() async {
    final dir = Directory(await _versionDir());
    if (!dir.existsSync()) return 0;
    var size = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) size += await entity.length();
    }
    return size;
  }

  Future<PronunciationLibraryPaths> downloadAndInstall({
    CancelToken? cancelToken,
    void Function(double progress)? onDownloadProgress,
    void Function()? onInstalling,
  }) async {
    final root = await _root();
    await Directory(root).create(recursive: true);
    final archive = File(p.join(root, '_dl_$pronunciationLibraryVersion.zip'));
    final staging = Directory(
      p.join(root, '_staging_$pronunciationLibraryVersion'),
    );
    try {
      await _writePendingPhase(_downloadPhase);
      if (!await _matchesExpectedHash(archive)) {
        await _downloader.download(
          uri: Uri.parse(_url),
          savePath: archive.path,
          identityKey: _sha256,
          allowResume: true,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            if (total != null && total > 0) {
              onDownloadProgress?.call((received / total).clamp(0, 1));
            }
          },
        );
      } else {
        onDownloadProgress?.call(1);
      }
      final actual = await sha256.bind(archive.openRead()).first;
      if (actual.toString() != _sha256) {
        await _deleteIfExists(archive);
        throw StateError('Pronunciation archive SHA-256 mismatch');
      }
      onInstalling?.call();
      await _writePendingPhase(_installPhase);
      if (staging.existsSync()) await staging.delete(recursive: true);
      await compute(_extractPronunciationZip, (
        archivePath: archive.path,
        outputPath: staging.path,
      ));
      final database = File(p.join(staging.path, 'pronunciation.sqlite'));
      final audio = Directory(p.join(staging.path, 'audio'));
      validatePronunciationDatabase(database.path);
      _validateAudioReferences(database.path, audio.path);
      await File(p.join(staging.path, 'install.json')).writeAsString(
        jsonEncode({'version': pronunciationLibraryVersion, 'sha256': _sha256}),
        flush: true,
      );
      final target = Directory(await _versionDir());
      final previous = Directory('${target.path}.previous');
      await _writePendingPhase(_replacePhase);
      if (previous.existsSync()) await previous.delete(recursive: true);
      if (target.existsSync()) {
        await target.rename(previous.path);
      }
      try {
        await staging.rename(target.path);
      } catch (_) {
        if (previous.existsSync() && !target.existsSync()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      if (previous.existsSync()) await previous.delete(recursive: true);
      await _deleteIfExists(await _pendingInstallFile());
      await _deleteIfExists(archive);
      return PronunciationLibraryPaths(
        database: p.join(target.path, 'pronunciation.sqlite'),
        audioDirectory: p.join(target.path, 'audio'),
      );
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
  }

  Future<void> _writePendingPhase(String phase) async {
    final file = await _pendingInstallFile();
    await file.writeAsString(
      jsonEncode({'version': pronunciationLibraryVersion, 'phase': phase}),
      flush: true,
    );
  }

  Future<String?> _readPendingPhase(File file) async {
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['version'] == pronunciationLibraryVersion) {
        final phase = data['phase'];
        if (phase is String) return phase;
      }
    } catch (_) {}
    // 不可解析的旧标记仍代表需要重新下载，避免误把半成品当完成。
    return _downloadPhase;
  }

  Future<bool> _matchesExpectedHash(File file) async {
    if (!file.existsSync()) return false;
    final actual = await sha256.bind(file.openRead()).first;
    return actual.toString() == _sha256;
  }

  Future<void> _deleteDownloadArtifacts(String root) async {
    final archive = File(p.join(root, '_dl_$pronunciationLibraryVersion.zip'));
    await _deleteIfExists(archive);
    await _deleteIfExists(File('${archive.path}.part'));
    await _deleteIfExists(File('${archive.path}.part.meta.json'));
  }

  Future<void> _deleteIfExists(File file) async {
    if (file.existsSync()) await file.delete();
  }

  void dispose() {
    if (_ownsDio) _dio.close();
  }
}

/// 在后台 isolate 解压发音包，只接收可发送的路径值，避免捕获 UI 回调和状态对象。
void _extractPronunciationZip(({String archivePath, String outputPath}) paths) {
  final archive = ZipDecoder().decodeBytes(
    File(paths.archivePath).readAsBytesSync(),
  );
  final output = Directory(paths.outputPath)..createSync(recursive: true);
  for (final entry in archive) {
    final name = p.posix.normalize(entry.name);
    final allowed = entry.isFile
        ? name == 'pronunciation.sqlite' ||
              RegExp(r'^audio/[^/]+\.opus$').hasMatch(name)
        : name == 'audio';
    if (!allowed ||
        p.posix.isAbsolute(name) ||
        name.split('/').contains('..') ||
        entry.isSymbolicLink) {
      throw StateError('Invalid pronunciation archive entry: ${entry.name}');
    }
    if (!entry.isFile) continue;
    final file = File(p.joinAll([output.path, ...name.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.content as List<int>, flush: true);
  }
}

void _validateAudioReferences(String databasePath, String audioDirectory) {
  final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
  try {
    final rows = database.select(
      'SELECT audio_filename FROM pronunciation_audio',
    );
    for (final row in rows) {
      final filename = row['audio_filename'] as String;
      if (filename != p.basename(filename) ||
          !filename.endsWith('.opus') ||
          !File(p.join(audioDirectory, filename)).existsSync()) {
        throw StateError('Pronunciation audio files missing or invalid');
      }
    }
  } finally {
    database.dispose();
  }
}
