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

  Future<PronunciationLibraryPaths?> installedPaths() async {
    final dir = await _versionDir();
    final marker = File(p.join(dir, 'install.json'));
    final database = File(p.join(dir, 'pronunciation.sqlite'));
    final audio = Directory(p.join(dir, 'audio'));
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
      await _downloader.download(
        uri: Uri.parse(_url),
        savePath: archive.path,
        identityKey: _sha256,
        allowResume: false,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            onDownloadProgress?.call((received / total).clamp(0, 1));
          }
        },
      );
      final actual = await sha256.bind(archive.openRead()).first;
      if (actual.toString() != _sha256) {
        throw StateError('Pronunciation archive SHA-256 mismatch');
      }
      onInstalling?.call();
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
      return PronunciationLibraryPaths(
        database: p.join(target.path, 'pronunciation.sqlite'),
        audioDirectory: p.join(target.path, 'audio'),
      );
    } finally {
      if (archive.existsSync()) await archive.delete();
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
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
