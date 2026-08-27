import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'app_logger.dart';
import 'reliable_http_downloader.dart';
import 'resource_install_manifest.dart';

/// 固定 CDN 资源归档的通用下载与原子安装流程。
///
/// 资源自身只负责把归档解压并校验到 staging 目录，下载、校验、替换、清理
/// 和安装清单始终走同一套实现，避免词典与发音包产生行为差异。
class ResourceArchiveInstaller {
  ResourceArchiveInstaller(this._downloader);

  final ReliableHttpDownloader _downloader;

  Future<void> install({
    required Directory root,
    required Directory target,
    Directory? downloadDirectory,
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
    final downloadRoot = downloadDirectory ?? root;
    await downloadRoot.create(recursive: true);
    final archive = File(
      p.join(downloadRoot.path, '_download_$resourceId.zip'),
    );
    final staging = Directory(p.join(root.path, '_staging_$resourceId'));
    try {
      AppLogger.log(
        'ResourceInstall',
        'downloading resource=$resourceId url=$uri',
      );
      await _downloader.download(
        uri: uri,
        savePath: archive.path,
        identityKey: expectedSha256,
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
          'Resource archive SHA-256 mismatch: expected=$expectedSha256 '
          'actual=$actualSha256',
        );
      }
      AppLogger.log(
        'ResourceInstall',
        'archive verified resource=$resourceId bytes=${await archive.length()}',
      );
      onInstalling?.call();
      if (staging.existsSync()) await staging.delete(recursive: true);
      await extractAndValidate(archive, staging);
      await writeResourceInstallManifest(
        staging,
        resourceId: resourceId,
        installAt: DateTime.now(),
      );
      AppLogger.log(
        'ResourceInstall',
        'install manifest written resource=$resourceId',
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
      AppLogger.log('ResourceInstall', 'install finished resource=$resourceId');
    } finally {
      if (archive.existsSync()) await archive.delete();
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
  }
}
