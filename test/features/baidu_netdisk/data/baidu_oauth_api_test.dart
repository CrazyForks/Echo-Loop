import 'package:dio/dio.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_oauth_api.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_netdisk_error.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_oauth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio dio;
  late BackendBaiduOAuthApi api;

  setUp(() {
    dio = _MockDio();
    api = BackendBaiduOAuthApi.withDio(dio);
  });

  Response<Object?> response(Object? data) => Response<Object?>(
    requestOptions: RequestOptions(path: '/'),
    statusCode: 200,
    data: data,
  );

  group('BackendBaiduOAuthApi', () {
    test('createSession 提交平台并解析会话', () async {
      when(
        () => dio.post<Object?>(
          '/api/v1/netdisk/baidu/oauth/session',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => response({
          'sessionId': 'sid',
          'pollToken': 'poll',
          'authorizationUrl': 'https://openapi.baidu.com/oauth/2.0/authorize',
          'expiresAt': '2026-07-18T12:00:00Z',
          'pollIntervalSeconds': 2,
        }),
      );

      final session = await api.createSession(
        BaiduNetdiskPlatform.ios,
        forceLogin: false,
      );

      expect(session.sessionId, 'sid');
      final captured =
          verify(
                () => dio.post<Object?>(
                  '/api/v1/netdisk/baidu/oauth/session',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map;
      expect(captured['platform'], 'ios');
      expect(captured.containsKey('forceLogin'), isFalse);
    });

    test('createSession 在主动退出后的下一次授权提交 forceLogin', () async {
      when(
        () => dio.post<Object?>(
          '/api/v1/netdisk/baidu/oauth/session',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => response({
          'sessionId': 'sid',
          'pollToken': 'poll',
          'authorizationUrl': 'https://openapi.baidu.com/oauth/2.0/authorize',
          'expiresAt': '2026-07-18T12:00:00Z',
          'pollIntervalSeconds': 2,
        }),
      );

      await api.createSession(BaiduNetdiskPlatform.android, forceLogin: true);

      final captured =
          verify(
                () => dio.post<Object?>(
                  '/api/v1/netdisk/baidu/oauth/session',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map;
      expect(captured, {'platform': 'android', 'forceLogin': true});
    });

    test('status 提交 sessionId 和 pollToken', () async {
      when(
        () => dio.post<Object?>(
          '/api/v1/netdisk/baidu/oauth/session/status',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => response({'status': 'pending'}));

      final status = await api.fetchStatus(sessionId: 'sid', pollToken: 'poll');

      expect(status.phase.name, 'pending');
      final captured =
          verify(
                () => dio.post<Object?>(
                  '/api/v1/netdisk/baidu/oauth/session/status',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map;
      expect(captured['sessionId'], 'sid');
      expect(captured['pollToken'], 'poll');
    });

    test('acknowledge 调用确认接口', () async {
      when(
        () => dio.post<Object?>(
          '/api/v1/netdisk/baidu/oauth/session/acknowledge',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => response(<String, Object?>{}));

      await api.acknowledge(sessionId: 'sid', pollToken: 'poll');

      verify(
        () => dio.post<Object?>(
          '/api/v1/netdisk/baidu/oauth/session/acknowledge',
          data: any(named: 'data'),
        ),
      ).called(1);
    });

    test('refresh 解析完整 credential bundle', () async {
      when(
        () => dio.post<Object?>(
          '/api/v1/netdisk/baidu/oauth/refresh',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => response({
          'accessToken': 'access2',
          'refreshToken': 'refresh2',
          'expiresAt': '2026-08-17T12:00:00Z',
          'scope': 'basic,netdisk',
        }),
      );

      final credential = await api.refresh(refreshToken: 'refresh1');

      expect(credential.accessToken, 'access2');
      expect(credential.refreshToken, 'refresh2');
    });

    test('统一错误体映射为 BaiduNetdiskApiError', () async {
      when(
        () => dio.post<Object?>(
          '/api/v1/netdisk/baidu/oauth/refresh',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/refresh'),
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/refresh'),
            statusCode: 401,
            data: {
              'error': {
                'code': 'reauthorization_required',
                'message': 'Reauthorize.',
              },
            },
          ),
        ),
      );

      expect(
        api.refresh(refreshToken: 'bad'),
        throwsA(
          isA<BaiduNetdiskApiError>().having(
            (error) => error.code,
            'code',
            BaiduNetdiskOAuthErrorCode.reauthorizationRequired,
          ),
        ),
      );
    });
  });
}
