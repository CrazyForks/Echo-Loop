/// Kokoro（Echo Loop TTS）模型下载、校验、缓存管理。
///
/// 与 Whisper 不同，Kokoro 含 `espeak-ng-data` 目录树，故托管为单个 `tar.gz`
/// 归档：下载归档 → 校验整包 SHA-256 → 流式解包到模型目录 → 校验关键文件存在。
/// 下载基于 `ReliableHttpDownloader`（同 `PiperModelManager`），`allowResume: false`
/// 保证归档下载失败/取消时不留任何残留。
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
import 'tts_engine.dart' show KokoroModelVariant;

// 复用 ASR 的下载状态/进度类型（已是通用命名，避免重复定义）。
export '../asr/asr_model_manager.dart'
    show AsrModelDownloadStatus, AsrModelDownloadProgress;
// 重导出变体枚举，便于管理器使用方（main/provider）无需再单独 import。
export 'tts_engine.dart' show KokoroModelVariant;

/// CDN 基础 URL。
const _cdnBase = 'https://cdn.echo-loop.top';

/// 默认（推荐）模型变体：fp32 未量化，速度/效果最佳。
const kokoroDefaultVariant = KokoroModelVariant.fp32;

/// 单个 Kokoro 模型变体的下载/解析规格（不可变）。
///
/// 归档必须用 gzip（非 bz2，archive 包 bz2 为纯 Dart 解码、移动端过慢）且不得含
/// macOS 扩展属性/AppleDouble（`tar --no-xattrs --no-mac-metadata` +
/// `COPYFILE_DISABLE=1`）——否则 PAX 扩展头会让 archive 的 `utf8.decode` 抛
/// `FormatException: Missing extension byte`（见 CLAUDE.md §7.17）。换归档须同步
/// 改 [sha256]，且先传 CDN 再改常量/发版。
class KokoroModelSpec {
  /// 变体标识。
  final KokoroModelVariant variant;

  /// 模型 ID（= 本地目录名）。
  final String id;

  /// 归档相对路径（拼到 `$base/model/$path`）。
  final String archivePath;

  /// 归档整包 SHA-256。
  final String sha256;

  /// 模型 onnx 文件名（fp32 `model.onnx` / int8 `model.int8.onnx`）。
  final String modelFileName;

  const KokoroModelSpec({
    required this.variant,
    required this.id,
    required this.archivePath,
    required this.sha256,
    required this.modelFileName,
  });
}

/// 两个变体的规格注册表。
const kokoroModelSpecs = <KokoroModelVariant, KokoroModelSpec>{
  KokoroModelVariant.fp32: KokoroModelSpec(
    variant: KokoroModelVariant.fp32,
    id: 'kokoro-en-v0_19',
    archivePath: 'tts/kokoro-en-v0_19.tar.gz',
    sha256: 'd97c85ba5777bc226eca3a40312bb29dd8fd0e77546d4100abb7243b9b6ad137',
    modelFileName: 'model.onnx',
  ),
  KokoroModelVariant.int8: KokoroModelSpec(
    variant: KokoroModelVariant.int8,
    // `-v2` 为重打干净包后的版本化 key（旧裸 URL 被 Cloudflare 边缘缓存了旧
    // 污染包，见 §7.17）；换归档须 bump 版本号绕开缓存。
    id: 'kokoro-en-v0_19-int8',
    archivePath: 'tts/kokoro-en-v0_19-int8-v2.tar.gz',
    sha256: '70fd7ff687d08245f9409557f58072f43eb8a5bf8a90e98dd3bb7f60e05b4b07',
    modelFileName: 'model.int8.onnx',
  ),
};

/// 按变体取规格。
KokoroModelSpec kokoroSpecOf(KokoroModelVariant variant) =>
    kokoroModelSpecs[variant]!;

/// 解包后必须存在的关键文件名（在模型目录下递归定位）。
const _kokoroVoicesFile = 'voices.bin';
const _kokoroTokensFile = 'tokens.txt';

/// espeak-ng G2P 数据目录名（关键，缺失则合成失败）。
const _kokoroDataDirName = 'espeak-ng-data';

/// Kokoro 引擎初始化所需的本地绝对路径集合。
class KokoroModelPaths {
  /// `model.int8.onnx` 绝对路径。
  final String model;

  /// `voices.bin` 绝对路径。
  final String voices;

  /// `tokens.txt` 绝对路径。
  final String tokens;

  /// `espeak-ng-data` 目录绝对路径。
  final String dataDir;

  const KokoroModelPaths({
    required this.model,
    required this.voices,
    required this.tokens,
    required this.dataDir,
  });
}

/// Kokoro 模型管理器（绑定单个变体规格）。
///
/// 每个变体一个实例（见 `kokoroModelManagerProvider` 的 family）；方法均针对
/// 本实例绑定的 [spec] 操作，互不干扰，故各模型可独立下载/删除/校验。
class KokoroModelManager {
  /// `ReliableHttpDownloader` 接口本身不提供释放能力，[dispose] 需要靠持有
  /// 同一个 [_dio] 来关闭底层 HTTP 客户端。
  late final Dio _dio;
  late final ReliableHttpDownloader _downloader;

  /// 本管理器绑定的模型规格（决定目录名/归档/SHA/模型文件名）。
  final KokoroModelSpec spec;

  /// 下载基地址覆盖（仅测试）。
  final String? baseUrlOverride;

  /// 模型存储根目录解析器（仅测试覆盖；默认 `${appSupport}/tts-models`）。
  final Future<String> Function()? modelsRootResolver;

  KokoroModelManager({
    Dio? dio,
    KokoroModelSpec? spec,
    this.baseUrlOverride,
    this.modelsRootResolver,
  }) : spec = spec ?? kokoroSpecOf(kokoroDefaultVariant) {
    _dio = dio ?? Dio();
    _downloader = DioReliableHttpDownloader(dio: _dio);
  }

  /// 模型存储根目录。
  Future<String> get _modelsRoot async {
    if (modelsRootResolver != null) return modelsRootResolver!();
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'tts-models');
  }

  /// Kokoro 模型本地目录。
  Future<String> modelDir() async => p.join(await _modelsRoot, spec.id);

  /// 模型是否已下载且关键文件齐全。
  Future<bool> isModelDownloaded() async {
    final dir = Directory(await modelDir());
    if (!dir.existsSync()) return false;
    return await _resolvePaths(dir) != null;
  }

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

  /// 解析引擎所需文件路径；任一关键文件缺失返回 null。
  Future<KokoroModelPaths> kokoroConfigPaths() async {
    final dir = Directory(await modelDir());
    final paths = await _resolvePaths(dir);
    if (paths == null) {
      throw StateError('Kokoro model files missing under ${dir.path}');
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
    final archiveFile = File(p.join(root, '_dl_${spec.id}.tar.gz'));
    final baseUrl = baseUrlOverride ?? _cdnBase;
    final url = '$baseUrl/model/${spec.archivePath}';
    AppLogger.log('KokoroModel', '┌ downloadModel dir=$dir url=$url');

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
        identityKey: spec.sha256,
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

      // 2. 校验整包 SHA-256。
      final actual = await _computeSha256(archiveFile);
      if (actual != spec.sha256) {
        throw StateError(
          'Kokoro archive SHA-256 mismatch: '
          'expected=${spec.sha256} actual=$actual',
        );
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
        throw StateError('Kokoro key files missing after extraction in $dir');
      }

      onProgress?.call(
        const AsrModelDownloadProgress(
          status: AsrModelDownloadStatus.downloaded,
          progress: 1.0,
        ),
      );
      AppLogger.log('KokoroModel', '└ downloadModel done dir=$dir');
      return dir;
    } finally {
      // 无论成功失败都清理临时归档（98MB，不留垃圾）。
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
  /// 兼容归档解包后文件在根目录或某子目录下两种布局。
  Future<KokoroModelPaths?> _resolvePaths(Directory dir) async {
    final model = await _findFile(dir, spec.modelFileName);
    final voices = await _findFile(dir, _kokoroVoicesFile);
    final tokens = await _findFile(dir, _kokoroTokensFile);
    final dataDir = await _findDir(dir, _kokoroDataDirName);
    if (model == null || voices == null || tokens == null || dataDir == null) {
      return null;
    }
    return KokoroModelPaths(
      model: model,
      voices: voices,
      tokens: tokens,
      dataDir: dataDir,
    );
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
