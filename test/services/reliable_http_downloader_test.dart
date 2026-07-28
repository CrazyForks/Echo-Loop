import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:echo_loop/services/reliable_http_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _QueuedResponse {
  const _QueuedResponse(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final List<int> body;
  final Map<String, List<String>> headers;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responses);

  final List<_QueuedResponse> responses;
  final requestHeaders = <Map<String, Object?>>[];
  final requestUris = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestHeaders.add(Map<String, Object?>.from(options.headers));
    requestUris.add(options.uri);
    final response = responses.removeAt(0);
    return ResponseBody(
      Stream<Uint8List>.fromIterable([Uint8List.fromList(response.body)]),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('DioReliableHttpDownloader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reliable-download-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    DioReliableHttpDownloader downloaderWith(_RecordingAdapter adapter) {
      final dio = Dio();
      dio.httpClientAdapter = adapter;
      return DioReliableHttpDownloader(dio: dio);
    }

    File targetFile(String name) => File(p.join(tempDir.path, name));

    test('首次下载成功后原子落盘并清理 part/meta', () async {
      final adapter = _RecordingAdapter([
        const _QueuedResponse(
          200,
          [1, 2, 3],
          headers: {
            'content-length': ['3'],
          },
        ),
      ]);
      final target = targetFile('lesson.mp3');

      final result = await downloaderWith(adapter).download(
        uri: Uri.parse('https://example.com/lesson.mp3'),
        savePath: target.path,
        expectedSize: 3,
        identityKey: 'file:1',
      );

      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(await File('${target.path}.part').exists(), isFalse);
      expect(await File('${target.path}.part.meta.json').exists(), isFalse);
      expect(result.bytesWritten, 3);
      expect(result.resumed, isFalse);
    });

    test('已有匹配 part 时发送 Range 并按 206 追加续传', () async {
      final target = targetFile('lesson.mp3');
      await File('${target.path}.part').writeAsBytes([1, 2, 3]);
      await File(
        '${target.path}.part.meta.json',
      ).writeAsString('{"identityKey":"file:1","downloadedBytes":3}');
      final adapter = _RecordingAdapter([
        const _QueuedResponse(
          206,
          [4, 5],
          headers: {
            'content-range': ['bytes 3-4/5'],
            'content-length': ['2'],
          },
        ),
      ]);

      final result = await downloaderWith(adapter).download(
        uri: Uri.parse('https://example.com/lesson.mp3'),
        savePath: target.path,
        expectedSize: 5,
        identityKey: 'file:1',
      );

      expect(adapter.requestHeaders.single['Range'], 'bytes=3-');
      expect(await target.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(result.resumed, isTrue);
    });

    test('手动跟随 redirect 并保留下载请求头', () async {
      final target = targetFile('lesson.mp3');
      await File('${target.path}.part').writeAsBytes([1, 2, 3]);
      await File(
        '${target.path}.part.meta.json',
      ).writeAsString('{"identityKey":"file:1","downloadedBytes":3}');
      final adapter = _RecordingAdapter([
        const _QueuedResponse(
          302,
          [],
          headers: {
            'location': ['https://cdn.example.com/lesson.mp3?sign=ok'],
          },
        ),
        const _QueuedResponse(
          206,
          [4, 5],
          headers: {
            'content-range': ['bytes 3-4/5'],
            'content-length': ['2'],
          },
        ),
      ]);

      final result = await downloaderWith(adapter).download(
        uri: Uri.parse('https://example.com/lesson.mp3'),
        savePath: target.path,
        headers: const {'User-Agent': 'pan.baidu.com'},
        expectedSize: 5,
        identityKey: 'file:1',
      );

      expect(adapter.requestUris, [
        Uri.parse('https://example.com/lesson.mp3'),
        Uri.parse('https://cdn.example.com/lesson.mp3?sign=ok'),
      ]);
      expect(adapter.requestHeaders, [
        containsPair('User-Agent', 'pan.baidu.com'),
        containsPair('User-Agent', 'pan.baidu.com'),
      ]);
      expect(adapter.requestHeaders, [
        containsPair('Range', 'bytes=3-'),
        containsPair('Range', 'bytes=3-'),
      ]);
      expect(await target.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(result.resumed, isTrue);
    });

    test('服务端忽略 Range 返回 200 时丢弃旧 part 并从头写入', () async {
      final target = targetFile('lesson.mp3');
      await File('${target.path}.part').writeAsBytes([9, 9, 9]);
      await File(
        '${target.path}.part.meta.json',
      ).writeAsString('{"identityKey":"file:1","downloadedBytes":3}');
      final adapter = _RecordingAdapter([
        const _QueuedResponse(200, [1, 2, 3, 4]),
      ]);

      final result = await downloaderWith(adapter).download(
        uri: Uri.parse('https://example.com/lesson.mp3'),
        savePath: target.path,
        expectedSize: 4,
        identityKey: 'file:1',
      );

      expect(adapter.requestHeaders.single['Range'], 'bytes=3-');
      expect(await target.readAsBytes(), [1, 2, 3, 4]);
      expect(result.resumed, isFalse);
    });

    test('416 且本地 part 大小匹配时直接完成', () async {
      final target = targetFile('lesson.mp3');
      await File('${target.path}.part').writeAsBytes([1, 2, 3]);
      await File(
        '${target.path}.part.meta.json',
      ).writeAsString('{"identityKey":"file:1","downloadedBytes":3}');
      final adapter = _RecordingAdapter([const _QueuedResponse(416, [])]);

      final result = await downloaderWith(adapter).download(
        uri: Uri.parse('https://example.com/lesson.mp3'),
        savePath: target.path,
        expectedSize: 3,
        identityKey: 'file:1',
      );

      expect(adapter.requestHeaders.single['Range'], 'bytes=3-');
      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(result.resumed, isTrue);
    });

    test('identityKey 不匹配时删除旧 part 并普通下载', () async {
      final target = targetFile('lesson.mp3');
      await File('${target.path}.part').writeAsBytes([9, 9, 9]);
      await File(
        '${target.path}.part.meta.json',
      ).writeAsString('{"identityKey":"old","downloadedBytes":3}');
      final adapter = _RecordingAdapter([
        const _QueuedResponse(200, [1, 2]),
      ]);

      await downloaderWith(adapter).download(
        uri: Uri.parse('https://example.com/lesson.mp3'),
        savePath: target.path,
        expectedSize: 2,
        identityKey: 'new',
      );

      expect(adapter.requestHeaders.single.containsKey('Range'), isFalse);
      expect(await target.readAsBytes(), [1, 2]);
    });

    test('最终大小不匹配时报错并保留 part', () async {
      final target = targetFile('lesson.mp3');
      final adapter = _RecordingAdapter([
        const _QueuedResponse(200, [1, 2]),
      ]);

      await expectLater(
        downloaderWith(adapter).download(
          uri: Uri.parse('https://example.com/lesson.mp3'),
          savePath: target.path,
          expectedSize: 3,
          identityKey: 'file:1',
        ),
        throwsA(isA<ReliableDownloadException>()),
      );

      expect(await target.exists(), isFalse);
      expect(await File('${target.path}.part').readAsBytes(), [1, 2]);
    });
  });
}
