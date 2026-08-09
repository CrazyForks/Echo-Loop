import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:echo_loop/services/asr/asr_model_manager.dart';
import 'package:echo_loop/services/reliable_http_downloader.dart';

/// Mock HTTP client adapter for Dio that returns predefined file payloads
class MockHttpClientAdapter implements HttpClientAdapter {
  final Map<String, List<int>> filePayloads;

  MockHttpClientAdapter({required this.filePayloads});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final fileName = options.path.split('/').last;
    final payload = filePayloads[fileName];

    if (payload == null) {
      return ResponseBody(Stream.empty(), 404, headers: {});
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

class _TestAsrModelManager extends AsrModelManager {
  _TestAsrModelManager(
    this.rootDir, {
    required super.modelRegistryOverride,
    super.dio,
    super.baseUrlOverride,
  });

  final Directory rootDir;

  @override
  Future<String> modelDir(String modelId) async =>
      p.join(rootDir.path, modelId);
}

void main() {
  late Map<String, AsrModelManifest> manifest;

  setUp(() {
    final encoderBytes = List<int>.filled(100, 1);
    final decoderBytes = List<int>.filled(100, 2);
    final tokensBytes = List<int>.filled(50, 3);

    manifest = {
      'test-model': AsrModelManifest(
        files: [
          AsrModelFileSpec(
            path: 'encoder.onnx',
            sha256: sha256.convert(encoderBytes).toString(),
          ),
          AsrModelFileSpec(
            path: 'decoder.onnx',
            sha256: sha256.convert(decoderBytes).toString(),
          ),
          AsrModelFileSpec(
            path: 'tokens.txt',
            sha256: sha256.convert(tokensBytes).toString(),
          ),
        ],
      ),
    };
  });

  test('validateModel 对残缺模型返回 false', () async {
    final rootDir = await Directory.systemTemp.createTemp('asr-model-test');
    addTearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    final manager = _TestAsrModelManager(
      rootDir,
      modelRegistryOverride: manifest,
    );
    final modelDir = Directory(await manager.modelDir('test-model'));
    await modelDir.create(recursive: true);
    await File(
      p.join(modelDir.path, 'encoder.onnx'),
    ).writeAsBytes(List.filled(64, 1));
    await File(
      p.join(modelDir.path, 'decoder.onnx'),
    ).writeAsBytes(List.filled(100, 2));
    await File(
      p.join(modelDir.path, 'tokens.txt'),
    ).writeAsBytes(List.filled(50, 3));

    final result = await manager.validateModel('test-model');
    expect(result.isValid, isFalse);
    expect(result.filePath, 'encoder.onnx');
    expect(result.reason, 'SHA-256 mismatch');
  });

  test('downloadModel 会重新下载已存在但哈希不匹配的文件', () async {
    final rootDir = await Directory.systemTemp.createTemp('asr-redownload');
    final filePayloads = <String, List<int>>{
      'encoder.onnx': List<int>.filled(100, 1),
      'decoder.onnx': List<int>.filled(100, 2),
      'tokens.txt': List<int>.filled(50, 3),
    };

    // 使用 mock Dio adapter 而非真实 HTTP server
    final dio = Dio();
    dio.httpClientAdapter = MockHttpClientAdapter(filePayloads: filePayloads);

    addTearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    final manager = _TestAsrModelManager(
      rootDir,
      dio: dio,
      baseUrlOverride: 'http://mock.local',
      modelRegistryOverride: manifest,
    );
    final modelDir = Directory(await manager.modelDir('test-model'));
    await modelDir.create(recursive: true);
    await File(
      p.join(modelDir.path, 'encoder.onnx'),
    ).writeAsBytes(List.filled(100, 9));
    await File(
      p.join(modelDir.path, 'decoder.onnx'),
    ).writeAsBytes(filePayloads['decoder.onnx']!);
    await File(
      p.join(modelDir.path, 'tokens.txt'),
    ).writeAsBytes(filePayloads['tokens.txt']!);

    await manager.downloadModel('test-model');

    final encoder = File(p.join(modelDir.path, 'encoder.onnx'));
    expect(await encoder.length(), 100);
    final result = await manager.validateModel('test-model');
    expect(result.isValid, isTrue);
  });

  test('downloadModel 下载失败时抛出结构化 ReliableDownloadException', () async {
    final rootDir = await Directory.systemTemp.createTemp('asr-download-fail');
    addTearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    // adapter 未登记 encoder.onnx 的 payload，MockHttpClientAdapter 回 404，
    // 验证迁移到 ReliableHttpDownloader 后错误仍能正确抛出（不被吞掉），
    // 且已归类为结构化异常（迁移前是裸 DioException）。
    final dio = Dio();
    dio.httpClientAdapter = MockHttpClientAdapter(
      filePayloads: <String, List<int>>{
        'decoder.onnx': List<int>.filled(100, 2),
        'tokens.txt': List<int>.filled(50, 3),
      },
    );

    final manager = _TestAsrModelManager(
      rootDir,
      dio: dio,
      baseUrlOverride: 'http://mock.local',
      modelRegistryOverride: manifest,
    );

    await expectLater(
      manager.downloadModel('test-model'),
      throwsA(
        isA<ReliableDownloadException>()
            .having((e) => e.kind, 'kind', ReliableDownloadFailure.httpStatus)
            .having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('recommendModel 默认推荐 Balanced 档位', () {
    final manager = _TestAsrModelManager(
      Directory.systemTemp,
      modelRegistryOverride: manifest,
    );

    final model = manager.recommendModel(ramBytes: 0);

    expect(model.id, 'whisper-base-en-int8');
    expect(model.displayName, contains('Balanced'));
  });
}
