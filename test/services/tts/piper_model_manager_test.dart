import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:echo_loop/services/reliable_http_downloader.dart';
import 'package:echo_loop/services/tts/piper_model_manager.dart';
import 'package:echo_loop/services/tts/piper_model_catalog.dart';
import 'package:echo_loop/services/tts/tts_engine.dart';

/// 返回预置归档字节的 mock dio adapter（任何 .tar.gz 请求都返回该字节）。
class _MockArchiveAdapter implements HttpClientAdapter {
  _MockArchiveAdapter(this.payload);
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

/// 构造含关键文件的 tar.gz：`<id>.onnx` + `<id>.onnx.json`（应被忽略）+ tokens +
/// espeak-ng-data。Piper 单说话人，无 voices.bin。
List<int> _buildArchive({
  String onnxName = 'en_US-amy-medium.onnx',
  bool includeDataDir = true,
}) {
  final archive = Archive();
  archive.add(ArchiveFile(onnxName, 8, List<int>.filled(8, 1)));
  // 同名 json 元数据：必须不被当作模型挑中。
  archive.add(ArchiveFile('$onnxName.json', 4, List<int>.filled(4, 9)));
  archive.add(ArchiveFile('tokens.txt', 3, List<int>.filled(3, 3)));
  if (includeDataDir) {
    archive.add(
      ArchiveFile('espeak-ng-data/phontab', 5, List<int>.filled(5, 4)),
    );
  }
  final tar = TarEncoder().encodeBytes(archive);
  return GZipEncoder().encodeBytes(tar);
}

PiperModelManager _manager(Directory root, List<int> archive, {String? sha}) {
  final dio = Dio();
  dio.httpClientAdapter = _MockArchiveAdapter(archive);
  return PiperModelManager(
    dio: dio,
    baseUrlOverride: 'http://mock.local',
    voice: PiperVoice(
      id: 'en_US-amy-medium',
      displayName: 'Amy',
      accent: TtsAccent.us,
      isFemale: true,
      archivePath: 'tts/vits-piper-en_US-amy-medium.tar.gz',
      sha256: sha ?? sha256.convert(archive).toString(),
      estimatedDownloadBytes: 1024,
    ),
    modelsRootResolver: () async => root.path,
  );
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('piper-model-test');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('下载 → 校验 → 解包：onnx/tokens/espeak-ng-data 就位，忽略 .onnx.json', () async {
    final archive = _buildArchive();
    final manager = _manager(root, archive);

    final progresses = <double>[];
    await manager.downloadModel(onProgress: (p) => progresses.add(p.progress));

    expect(await manager.isModelDownloaded(), isTrue);
    final paths = await manager.piperConfigPaths();
    expect(p.basename(paths.model), 'en_US-amy-medium.onnx');
    expect(File(paths.model).existsSync(), isTrue);
    expect(File(paths.tokens).existsSync(), isTrue);
    expect(p.basename(paths.dataDir), 'espeak-ng-data');
    expect(progresses.last, 1.0);
  });

  test('SHA-256 不匹配 → 抛错且模型未安装，临时归档已清理', () async {
    final archive = _buildArchive();
    final manager = _manager(root, archive, sha: 'deadbeef');

    await expectLater(manager.downloadModel(), throwsA(isA<StateError>()));
    expect(await manager.isModelDownloaded(), isFalse);
    final leftovers = root.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.tar.gz'),
    );
    expect(leftovers, isEmpty);
  });

  test('归档下载网络失败 → 抛结构化异常且不留 .part 残留', () async {
    final dio = Dio();
    dio.httpClientAdapter = _AlwaysNotFoundAdapter();
    final manager = PiperModelManager(
      dio: dio,
      baseUrlOverride: 'http://mock.local',
      voice: const PiperVoice(
        id: 'en_US-amy-medium',
        displayName: 'Amy',
        accent: TtsAccent.us,
        isFemale: true,
        archivePath: 'tts/vits-piper-en_US-amy-medium.tar.gz',
        sha256: 'irrelevant',
        estimatedDownloadBytes: 1024,
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

  test('sha256 为空串（开发期占位）→ 跳过校验，仍可安装', () async {
    final archive = _buildArchive();
    final manager = _manager(root, archive, sha: '');
    await manager.downloadModel();
    expect(await manager.isModelDownloaded(), isTrue);
  });

  test('解包后缺 espeak-ng-data → 抛错', () async {
    final archive = _buildArchive(includeDataDir: false);
    final manager = _manager(root, archive);
    await expectLater(manager.downloadModel(), throwsA(isA<StateError>()));
    expect(await manager.isModelDownloaded(), isFalse);
  });

  test('deleteModel 删除本地目录；modelLocalSize 归零', () async {
    final manager = _manager(root, _buildArchive());
    await manager.downloadModel();
    expect(await manager.modelLocalSize(), greaterThan(0));
    await manager.deleteModel();
    expect(await manager.isModelDownloaded(), isFalse);
    expect(await manager.modelLocalSize(), 0);
  });
}
