import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:echo_loop/services/reliable_http_downloader.dart';
import 'package:echo_loop/services/tts/kokoro_model_manager.dart';

/// 返回预置归档字节的 mock dio adapter（按 URL 末段匹配）。
class _MockArchiveAdapter implements HttpClientAdapter {
  _MockArchiveAdapter(this.payload);

  /// 末段文件名 → 字节；命中返回 200，否则 404。
  final List<int> payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.path.endsWith('.tar.gz')) {
      return ResponseBody(const Stream.empty(), 404, headers: {});
    }
    return ResponseBody(
      Stream.fromIterable([Uint8List.fromList(payload)]),
      200,
      headers: {
        'content-length': [payload.length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 对任何请求都返回 404 的 mock adapter，用于模拟归档下载的网络失败。
class _AlwaysNotFoundAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(const Stream.empty(), 404, headers: {});

  @override
  void close({bool force = false}) {}
}

/// 构造一个含关键文件的 tar.gz 字节。
List<int> _buildArchive({bool includeDataDir = true}) {
  final archive = Archive();
  archive.add(ArchiveFile('model.int8.onnx', 8, List<int>.filled(8, 1)));
  archive.add(ArchiveFile('voices.bin', 4, List<int>.filled(4, 2)));
  archive.add(ArchiveFile('tokens.txt', 3, List<int>.filled(3, 3)));
  if (includeDataDir) {
    // 目录由文件路径隐式建立。
    archive.add(
      ArchiveFile('espeak-ng-data/phontab', 5, List<int>.filled(5, 4)),
    );
  }
  final tar = TarEncoder().encodeBytes(archive);
  return GZipEncoder().encodeBytes(tar);
}

KokoroModelManager _manager(Directory root, List<int> archive, {String? sha}) {
  final dio = Dio();
  dio.httpClientAdapter = _MockArchiveAdapter(archive);
  return KokoroModelManager(
    dio: dio,
    baseUrlOverride: 'http://mock.local',
    spec: KokoroModelSpec(
      variant: KokoroModelVariant.int8,
      id: 'test-model',
      archivePath: 'tts/test.tar.gz',
      sha256: sha ?? sha256.convert(archive).toString(),
      modelFileName: 'model.int8.onnx',
    ),
    modelsRootResolver: () async => root.path,
  );
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kokoro-model-test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('下载 → 校验 → 解包：关键文件就位且 isModelDownloaded 为真', () async {
    final archive = _buildArchive();
    final manager = _manager(root, archive);

    final progresses = <double>[];
    await manager.downloadModel(onProgress: (p) => progresses.add(p.progress));

    expect(await manager.isModelDownloaded(), isTrue);
    final paths = await manager.kokoroConfigPaths();
    expect(File(paths.model).existsSync(), isTrue);
    expect(File(paths.voices).existsSync(), isTrue);
    expect(File(paths.tokens).existsSync(), isTrue);
    expect(Directory(paths.dataDir).existsSync(), isTrue);
    expect(p.basename(paths.dataDir), 'espeak-ng-data');
    // 进度应抵达 1.0。
    expect(progresses.last, 1.0);
  });

  test('归档 SHA-256 不匹配 → 抛错且模型未安装', () async {
    final archive = _buildArchive();
    final manager = _manager(root, archive, sha: 'deadbeef');

    await expectLater(manager.downloadModel(), throwsA(isA<StateError>()));
    expect(await manager.isModelDownloaded(), isFalse);
    // 临时归档应被清理。
    final leftovers = root.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.tar.gz'),
    );
    expect(leftovers, isEmpty);
  });

  test('归档下载网络失败 → 抛结构化异常且不留 .part 残留', () async {
    final dio = Dio();
    dio.httpClientAdapter = _AlwaysNotFoundAdapter();
    final manager = KokoroModelManager(
      dio: dio,
      baseUrlOverride: 'http://mock.local',
      spec: const KokoroModelSpec(
        variant: KokoroModelVariant.int8,
        id: 'test-model',
        archivePath: 'tts/test.tar.gz',
        sha256: 'irrelevant',
        modelFileName: 'model.int8.onnx',
      ),
      modelsRootResolver: () async => root.path,
    );

    await expectLater(
      manager.downloadModel(),
      throwsA(
        isA<ReliableDownloadException>().having(
          (e) => e.kind,
          'kind',
          ReliableDownloadFailure.httpStatus,
        ),
      ),
    );
    final leftovers = root.listSync().whereType<File>();
    expect(leftovers, isEmpty);
  });

  test('解包后缺关键文件（无 espeak-ng-data）→ 抛错', () async {
    final archive = _buildArchive(includeDataDir: false);
    final manager = _manager(root, archive);

    await expectLater(manager.downloadModel(), throwsA(isA<StateError>()));
    expect(await manager.isModelDownloaded(), isFalse);
  });

  test('deleteModel 删除本地目录', () async {
    final archive = _buildArchive();
    final manager = _manager(root, archive);
    await manager.downloadModel();
    expect(await manager.isModelDownloaded(), isTrue);

    await manager.deleteModel();
    expect(await manager.isModelDownloaded(), isFalse);
    expect(await manager.modelLocalSize(), 0);
  });

  test('modelLocalSize 在下载后大于 0', () async {
    final archive = _buildArchive();
    final manager = _manager(root, archive);
    await manager.downloadModel();
    expect(await manager.modelLocalSize(), greaterThan(0));
  });
}
