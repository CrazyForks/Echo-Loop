import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../app_logger.dart';
import '../reliable_http_downloader.dart';
import '../resource_install_manifest.dart';

/// ASR 模型归档的下载、断点续传与原子安装流程。
///
/// 此实现刻意只服务 ASR，避免本次改动影响既有 TTS 下载安装机制；未来如需
/// 统一资源安装策略，应以独立任务重新评估并迁移各调用方。
class AsrArchiveInstaller {
  AsrArchiveInstaller(this._downloader);

  final ReliableHttpDownloader _downloader;

  Future<void> install({
    required Directory root,
    required Directory target,
    required String resourceId,
    required Uri uri,
    required String expectedSha256,
    required Future<void> Function(File archive, Directory staging)
    extractAndValidate,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
    void Function()? onInstalling,
  }) async {
    await root.create(recursive: true);
    final archive = File(p.join(root.path, '_download_$resourceId.zip'));
    await _cleanupOrphanedStagingDirectories(root, resourceId);
    Directory? staging;
    try {
      AppLogger.log('AsrInstall', 'downloading resource=$resourceId url=$uri');
      await _downloader.download(
        uri: uri,
        savePath: archive.path,
        identityKey: expectedSha256,
        // 网络中断或应用退出时保留 `.part` 和元数据，下一次同版本资源
        // 使用 SHA-256 identityKey 发起 HTTP Range 续传。
        allowResume: true,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        },
      );
      final actualSha256 = await sha256.bind(archive.openRead()).first;
      if (actualSha256.toString() != expectedSha256) {
        throw StateError(
          'ASR archive SHA-256 mismatch: expected=$expectedSha256 '
          'actual=$actualSha256',
        );
      }
      staging = await root.createTemp('_staging_${resourceId}_');
      onInstalling?.call();
      await extractAndValidate(archive, staging);
      await writeResourceInstallManifest(
        staging,
        resourceId: resourceId,
        installAt: DateTime.now(),
      );

      final previous = Directory('${target.path}.previous');
      if (previous.existsSync()) await previous.delete(recursive: true);
      if (target.existsSync()) await target.rename(previous.path);
      try {
        await staging.rename(target.path);
      } catch (_) {
        if (previous.existsSync() && !target.existsSync()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      if (previous.existsSync()) await previous.delete(recursive: true);
      AppLogger.log('AsrInstall', 'install finished resource=$resourceId');
    } finally {
      await _deleteFileQuietly(archive);
      if (staging != null) await _deleteDirectoryQuietly(staging);
    }
  }

  /// 丢弃用户明确取消的资源下载残留。
  ///
  /// 仅显式取消调用此方法；网络失败和进程中断保留 `.part`，以便后续续传。
  Future<void> discardPartial({
    required Directory root,
    required String resourceId,
  }) async {
    final archive = File(p.join(root.path, '_download_$resourceId.zip'));
    await _deleteFileQuietly(archive);
    await _deleteFileQuietly(File('${archive.path}.part'));
    await _deleteFileQuietly(File('${archive.path}.part.meta.json'));
    await _cleanupOrphanedStagingDirectories(root, resourceId);
  }

  Future<void> _cleanupOrphanedStagingDirectories(
    Directory root,
    String resourceId,
  ) async {
    if (!root.existsSync()) return;
    final prefix = '_staging_${resourceId}_';
    final legacyName = '_staging_$resourceId';
    await for (final entity in root.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory &&
          (name == legacyName || name.startsWith(prefix))) {
        await _deleteDirectoryQuietly(entity);
      }
    }
  }

  Future<void> _deleteFileQuietly(File file) async {
    if (!file.existsSync()) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await file.delete();
        return;
      } on FileSystemException catch (error, stackTrace) {
        if (attempt == 2) {
          AppLogger.log(
            'AsrInstall',
            'cleanup file failed path=${file.path} error=$error\n$stackTrace',
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> _deleteDirectoryQuietly(Directory directory) async {
    if (!directory.existsSync()) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException catch (error, stackTrace) {
        if (attempt == 2) {
          AppLogger.log(
            'AsrInstall',
            'cleanup directory failed path=${directory.path} error=$error\n$stackTrace',
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}
