/// Piper VITS 模型下载、校验、缓存管理（按音色，每音色一个独立模型）。
///
/// 镜像 `KokoroModelManager`，但绑定单个 [PiperVoice]（而非 Kokoro 的精度变体）：
/// 每个音色一个 `.tar.gz` 归档，下载 → 校验整包 SHA-256 → 流式解包到以音色 id
/// 命名的目录 → 校验关键文件（`*.onnx` / `tokens.txt` / `espeak-ng-data/`）。
///
/// 与 Kokoro 的唯一差异：Piper 为单说话人，**无 `voices.bin`**；模型文件名由各音色
/// 决定（如 `en_US-amy-medium.onnx`），故按扩展名定位 `.onnx`（排除 `.onnx.json`）。
/// 归档约束同 §7.17（gzip、无 macOS xattr、换包先传 CDN 再改 SHA）。
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_logger.dart';
import '../asr/asr_model_manager.dart'
    show AsrModelDownloadStatus, AsrModelDownloadProgress;
import '../reliable_http_downloader.dart';
import 'piper_model_catalog.dart';
import '../resource_install_manifest.dart';

// 复用 ASR 的下载状态/进度类型（已是通用命名，避免重复定义）。
export '../asr/asr_model_manager.dart'
    show AsrModelDownloadStatus, AsrModelDownloadProgress;

/// Piper 引擎初始化所需的本地绝对路径集合（无 voices.bin）。
class PiperModelPaths {
  /// `*.onnx` 模型绝对路径（如 `en_US-amy-medium.onnx`）。
  final String model;

  /// `tokens.txt` 绝对路径。
  final String tokens;

  /// `espeak-ng-data` 目录绝对路径。
  final String dataDir;

  const PiperModelPaths({
    required this.model,
    required this.tokens,
    required this.dataDir,
  });
}

/// Piper 模型管理器（绑定单个音色 [voice]）。
///
/// 每个音色一个实例（见 `piperModelManagerProvider` 的 family）；方法均针对本实例
/// 绑定的音色操作，互不干扰，故各音色可独立下载/删除/校验。
class PiperModelManager {
  /// `ReliableHttpDownloader` 接口本身不提供释放能力，[dispose] 需要靠持有
  /// 同一个 [_dio] 来关闭底层 HTTP 客户端。
  late final Dio _dio;
  late final ReliableHttpDownloader _downloader;

  /// 本管理器绑定的音色（决定目录名/归档/SHA）。
  final PiperVoice voice;

  /// 下载基地址覆盖（仅测试）。
  final String? baseUrlOverride;

  /// 模型存储根目录解析器（仅测试覆盖；默认 `${appSupport}/tts-models`）。
  final Future<String> Function()? modelsRootResolver;

  PiperModelManager({
    required this.voice,
    Dio? dio,
    this.baseUrlOverride,
    this.modelsRootResolver,
  }) {
    // TTS 模型下载体积较大，但断网时不能无限等待；接收超时只限制长时间无数据。
    _dio =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
    _downloader = DioReliableHttpDownloader(dio: _dio);
  }

  /// 模型存储根目录（与 Kokoro 共用 `tts-models`，各音色子目录隔离）。
  Future<String> get _modelsRoot async {
    if (modelsRootResolver != null) return modelsRootResolver!();
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'tts-models');
  }

  /// 本音色模型本地目录（目录名 = 音色 id）。
  Future<String> modelDir() async => p.join(await _modelsRoot, voice.id);

  /// 模型是否已下载且关键文件齐全。
  Future<bool> isModelDownloaded() async {
    final dir = Directory(await modelDir());
    if (!dir.existsSync()) return false;
    return await _resolvePaths(dir) != null;
  }

  /// 读取安装清单；ready 门控不读取 SharedPreferences。
  Future<ResourceInstallManifest?> readInstallManifest() async {
    final directory = Directory(await modelDir());
    final manifestFile = File(p.join(directory.path, 'install.json'));
    AppLogger.log(
      'PiperModel',
      '检查安装状态 resource=${voice.id} dir=${directory.path} '
          'dirExists=${directory.existsSync()} '
          'manifestExists=${manifestFile.existsSync()}',
    );
    final ResourceInstallManifest? manifest;
    try {
      manifest = await readResourceInstallManifest(directory);
    } on FormatException catch (error) {
      AppLogger.log('PiperModel', 'invalid install manifest: $error');
      return null;
    }
    if (manifest == null) {
      AppLogger.log('PiperModel', '检查结果 resource=${voice.id} manifest=null');
      return null;
    }
    if (manifest.resourceId != voice.id) {
      AppLogger.log(
        'PiperModel',
        '检查结果 resource=${voice.id} manifestResource=${manifest.resourceId} matched=false',
      );
      return null;
    }
    AppLogger.log(
      'PiperModel',
      '检查结果 resource=${voice.id} manifestResource=${manifest.resourceId} '
          'resourceSize=${manifest.resourceSize} matched=true',
    );
    return manifest;
  }

  /// 兼容旧调用方的安装标记检查。
  Future<bool> hasInstallMarker() async => await readInstallManifest() != null;

  /// 模型本地占用空间（字节，递归统计）。
  Future<int> modelLocalSize() async {
    final dir = Directory(await modelDir());
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// 解析引擎所需文件路径；任一关键文件缺失抛 [StateError]。
  Future<PiperModelPaths> piperConfigPaths() async {
    final dir = Directory(await modelDir());
    final paths = await _resolvePaths(dir);
    if (paths == null) {
      throw StateError('Piper model files missing under ${dir.path}');
    }
    return paths;
  }

  /// 下载并安装模型，通过 [onProgress] 报告进度，可经 [cancelToken] 取消。
  ///
  /// 流程：下载归档 → 校验 SHA-256 → 清空目录 → 流式解包 → 校验关键文件。
  Future<String> downloadModel({
    void Function(AsrModelDownloadProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await modelDir();
    final root = await _modelsRoot;
    await Directory(root).create(recursive: true);

    // 临时归档名必须以 `.tar.gz` 结尾，extractFileToDisk 据扩展名识别格式。
    final archiveFile = File(p.join(root, '_dl_${voice.id}.tar.gz'));
    final baseUrl = baseUrlOverride ?? piperCdnBaseUrl;
    final url = '$baseUrl/model/${voice.archivePath}';
    AppLogger.log('PiperModel', '┌ downloadModel dir=$dir url=$url');

    onProgress?.call(
      const AsrModelDownloadProgress(
        status: AsrModelDownloadStatus.downloading,
      ),
    );

    try {
      // 1. 下载归档（进度映射到 0..0.95，留 0.05 给校验+解包）。
      // allowResume: false——归档下载失败/取消必须不留任何残留（.part 也不留，
      // 与下方 finally 清理临时归档的既有设计一致，见类文档注释）。
      await _downloader.download(
        uri: Uri.parse(url),
        savePath: archiveFile.path,
        identityKey: voice.sha256.isEmpty ? null : voice.sha256,
        allowResume: false,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          final frac = (total != null && total > 0) ? received / total : 0.0;
          onProgress?.call(
            AsrModelDownloadProgress(
              status: AsrModelDownloadStatus.downloading,
              progress: (frac * 0.95).clamp(0.0, 0.95),
            ),
          );
        },
      );

      // 2. 校验整包 SHA-256（音色目录的 sha256 为空串时跳过校验：开发期占位，
      //    回填后才真正校验，见 piper_model_catalog.dart 的模型清单。
      if (voice.sha256.isNotEmpty) {
        final actual = await _computeSha256(archiveFile);
        if (actual != voice.sha256) {
          throw StateError(
            'Piper archive SHA-256 mismatch: '
            'expected=${voice.sha256} actual=$actual',
          );
        }
      }

      // 3. 清空旧目录后流式解包。
      final modelDirectory = Directory(dir);
      if (modelDirectory.existsSync()) {
        await modelDirectory.delete(recursive: true);
      }
      await modelDirectory.create(recursive: true);
      await extractFileToDisk(archiveFile.path, dir);

      // 4. 校验关键文件。
      if (await _resolvePaths(modelDirectory) == null) {
        throw StateError('Piper key files missing after extraction in $dir');
      }
      await writeResourceInstallManifest(
        modelDirectory,
        resourceId: voice.id,
        installAt: DateTime.now(),
      );

      onProgress?.call(
        const AsrModelDownloadProgress(
          status: AsrModelDownloadStatus.downloaded,
          progress: 1.0,
        ),
      );
      AppLogger.log('PiperModel', '└ downloadModel done dir=$dir');
      return dir;
    } finally {
      // 无论成功失败都清理临时归档，不留垃圾。
      if (archiveFile.existsSync()) {
        try {
          await archiveFile.delete();
        } catch (_) {}
      }
    }
  }

  /// 删除本地模型。
  Future<void> deleteModel() async {
    final dir = Directory(await modelDir());
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// 释放资源。
  void dispose() {
    _dio.close();
  }

  /// 在 [dir] 下递归定位关键文件；任一缺失返回 null。
  ///
  /// 兼容归档解包后文件在根目录或某子目录下两种布局。模型按扩展名 `.onnx` 定位
  /// （排除 sherpa 不需要的 `.onnx.json` 元数据）。
  Future<PiperModelPaths?> _resolvePaths(Directory dir) async {
    final model = await _findOnnx(dir);
    final tokens = await _findFile(dir, piperTokensFileName);
    final dataDir = await _findDir(dir, piperDataDirectoryName);
    if (model == null || tokens == null || dataDir == null) {
      return null;
    }
    return PiperModelPaths(model: model, tokens: tokens, dataDir: dataDir);
  }

  /// 递归定位首个 `.onnx`（排除 `.onnx.json`）。
  Future<String?> _findOnnx(Directory root) async {
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final name = p.basename(e.path);
        if (name.endsWith('.onnx') && !name.endsWith('.onnx.json')) {
          return e.path;
        }
      }
    }
    return null;
  }

  Future<String?> _findFile(Directory root, String name) async {
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File && p.basename(e.path) == name) return e.path;
    }
    return null;
  }

  Future<String?> _findDir(Directory root, String name) async {
    if (p.basename(root.path) == name) return root.path;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is Directory && p.basename(e.path) == name) return e.path;
    }
    return null;
  }

  Future<String> _computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
