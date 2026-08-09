import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echo_loop/services/dictionary_download_manager.dart';
import 'package:echo_loop/services/reliable_http_downloader.dart';

/// 按路径分发的 mock adapter：`/version.json` 返回预置版本信息，
/// `/dict.db.gz`（或其它约定路径）返回预置字节；其余 404。
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({
    required this.downloadUrl,
    required this.updatedAtIso,
    this.payload,
    this.downloadStatusCode = 200,
  });

  final String downloadUrl;
  final String updatedAtIso;
  final List<int>? payload;
  final int downloadStatusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/version.json')) {
      final body =
          '{"dictionary":{"en_zh":{"url":"$downloadUrl","updatedAt":"$updatedAtIso"}}}';
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }
    if (options.path == downloadUrl) {
      if (downloadStatusCode != 200 || payload == null) {
        return ResponseBody(
          const Stream.empty(),
          downloadStatusCode,
          headers: {},
        );
      }
      return ResponseBody(
        Stream.fromIterable([Uint8List.fromList(payload!)]),
        200,
        headers: {
          'content-length': [payload!.length.toString()],
        },
      );
    }
    return ResponseBody(const Stream.empty(), 404, headers: {});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fakeAppSupportDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeAppSupportDir = Directory.systemTemp.createTempSync(
      'dict_manager_support_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return fakeAppSupportDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (fakeAppSupportDir.existsSync()) {
      fakeAppSupportDir.deleteSync(recursive: true);
    }
  });

  DictionaryDownloadManager manager(_MockAdapter adapter) {
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    return DictionaryDownloadManager.withDio(dio);
  }

  test('download 成功 → 落盘 dict.db 且记录下载时间', () async {
    final payload = List<int>.filled(16, 7);
    final m = manager(
      _MockAdapter(
        downloadUrl: 'http://mock.local/dict.db.gz',
        updatedAtIso: '2026-01-01T00:00:00Z',
        payload: payload,
      ),
    );

    final path = await m.download('zh');

    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsBytesSync(), payload);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('dictionary_downloaded_at_en_zh'), isNotNull);
  });

  test('归档下载网络失败 → 抛结构化 ReliableDownloadException(httpStatus) 且不留残留', () async {
    final m = manager(
      _MockAdapter(
        downloadUrl: 'http://mock.local/dict.db.gz',
        updatedAtIso: '2026-01-01T00:00:00Z',
        downloadStatusCode: 404,
      ),
    );

    await expectLater(
      m.download('zh'),
      throwsA(
        isA<ReliableDownloadException>().having(
          (e) => e.kind,
          'kind',
          ReliableDownloadFailure.httpStatus,
        ),
      ),
    );

    final dictDir = Directory(
      p.join(fakeAppSupportDir.path, 'dictionary', 'en_zh'),
    );
    final leftovers = dictDir.existsSync()
        ? dictDir.listSync().whereType<File>()
        : const <File>[];
    expect(leftovers, isEmpty);
  });
}
