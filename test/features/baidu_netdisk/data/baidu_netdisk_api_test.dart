import 'package:dio/dio.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_netdisk_api.dart';
import 'package:echo_loop/features/baidu_netdisk/models/cloud_drive_models.dart';
import 'package:echo_loop/services/reliable_http_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

class _FakeReliableHttpDownloader implements ReliableHttpDownloader {
  Uri? uri;
  String? savePath;
  Map<String, String>? headers;
  int? expectedSize;
  String? identityKey;
  Object? error;

  @override
  Future<ReliableDownloadResult> download({
    required Uri uri,
    required String savePath,
    Map<String, String> headers = const <String, String>{},
    int? expectedSize,
    String? identityKey,
    bool allowResume = true,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    this.uri = uri;
    this.savePath = savePath;
    this.headers = headers;
    this.expectedSize = expectedSize;
    this.identityKey = identityKey;
    final error = this.error;
    if (error != null) throw error;
    onProgress?.call(expectedSize ?? 1, expectedSize);
    return ReliableDownloadResult(
      savePath: savePath,
      bytesWritten: expectedSize ?? 1,
      resumed: false,
    );
  }
}

void main() {
  late _MockDio metadataDio;
  late _FakeReliableHttpDownloader downloader;
  late DefaultBaiduNetdiskApi api;

  setUp(() {
    metadataDio = _MockDio();
    downloader = _FakeReliableHttpDownloader();
    api = DefaultBaiduNetdiskApi(
      metadataDio: metadataDio,
      downloader: downloader,
    );
  });

  Response<Object?> jsonResponse(Object? data) => Response<Object?>(
    requestOptions: RequestOptions(path: '/'),
    statusCode: 200,
    data: data,
  );

  group('DefaultBaiduNetdiskApi', () {
    test('listDirectory 调用百度列表接口并解析目录/文件', () async {
      when(
        () => metadataDio.get<Object?>(
          '/rest/2.0/xpan/file',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => jsonResponse({
          'errno': 0,
          'list': [
            {
              'fs_id': 1,
              'server_filename': 'Folder',
              'path': '/Folder',
              'isdir': 1,
              'size': 0,
              'server_mtime': 1784361000,
            },
            {
              'fs_id': '2',
              'server_filename': 'lesson.mp3',
              'path': '/Folder/lesson.mp3',
              'isdir': 0,
              'size': '123',
            },
          ],
        }),
      );

      final page = await api.listDirectory(
        accessToken: 'access-token',
        dir: '/Folder',
        start: 5,
        limit: 2,
      );

      expect(page.entries, hasLength(2));
      expect(page.entries.first.isDirectory, isTrue);
      expect(page.entries[1].name, 'lesson.mp3');
      expect(page.entries[1].extension, 'mp3');
      expect(page.nextStart, 7);
      expect(page.hasMore, isTrue);

      final query =
          verify(
                () => metadataDio.get<Object?>(
                  '/rest/2.0/xpan/file',
                  queryParameters: captureAny(named: 'queryParameters'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(query['method'], 'list');
      expect(query['access_token'], 'access-token');
      expect(query['dir'], '/Folder');
      expect(query['start'], 5);
      expect(query['limit'], 2);
    });

    test('fetchDownloadLink 调用 filemetas 并解析 dlink', () async {
      when(
        () => metadataDio.get<Object?>(
          '/rest/2.0/xpan/multimedia',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => jsonResponse({
          'errno': 0,
          'list': [
            {
              'fs_id': 42,
              'server_filename': 'lesson.m4a',
              'size': 456,
              'dlink': 'https://d.pcs.baidu.com/file/lesson',
            },
          ],
        }),
      );

      final link = await api.fetchDownloadLink(
        accessToken: 'access-token',
        fsId: 42,
      );

      expect(link.fsId, 42);
      expect(link.dlink, 'https://d.pcs.baidu.com/file/lesson');
      expect(link.size, 456);

      final query =
          verify(
                () => metadataDio.get<Object?>(
                  '/rest/2.0/xpan/multimedia',
                  queryParameters: captureAny(named: 'queryParameters'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(query['fsids'], '[42]');
      expect(query['dlink'], 1);
    });

    test('百度 errno -6 映射为 unauthorized', () async {
      when(
        () => metadataDio.get<Object?>(
          '/rest/2.0/xpan/file',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async =>
            jsonResponse({'errno': -6, 'errmsg': 'invalid access token'}),
      );

      expect(
        api.listDirectory(accessToken: 'bad'),
        throwsA(
          isA<BaiduNetdiskFileException>().having(
            (error) => error.kind,
            'kind',
            BaiduNetdiskFileErrorKind.unauthorized,
          ),
        ),
      );
    });

    test('downloadToFile 给 dlink 补 access_token 并带百度 UA', () async {
      await api.downloadToFile(
        accessToken: 'access-token',
        dlink: 'https://d.pcs.baidu.com/file/lesson?x=1',
        savePath: '/tmp/lesson.mp3',
        identityKey: 'baidu:42:123',
        expectedSize: 123,
      );

      expect(downloader.uri?.queryParameters['x'], '1');
      expect(downloader.uri?.queryParameters['access_token'], 'access-token');
      expect(downloader.savePath, '/tmp/lesson.mp3');
      expect(downloader.headers?['User-Agent'], 'pan.baidu.com');
      expect(downloader.identityKey, 'baidu:42:123');
      expect(downloader.expectedSize, 123);
    });

    test('downloadToFile 网络异常保留底层错误原因', () async {
      downloader.error = DioException(
        requestOptions: RequestOptions(path: '/file'),
        type: DioExceptionType.unknown,
        error: 'HandshakeException: Connection terminated during handshake',
      );

      await expectLater(
        api.downloadToFile(
          accessToken: 'access-token',
          dlink: 'https://d.pcs.baidu.com/file/lesson',
          savePath: '/tmp/lesson.mp3',
        ),
        throwsA(
          isA<BaiduNetdiskFileException>()
              .having(
                (error) => error.kind,
                'kind',
                BaiduNetdiskFileErrorKind.network,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Connection terminated during handshake'),
              ),
        ),
      );
    });
  });
}
