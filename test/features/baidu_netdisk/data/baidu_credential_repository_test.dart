import 'dart:async';

import 'package:clock/clock.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_credential_repository.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_credential_store.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_oauth_api.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_credential_bundle.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_netdisk_error.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_oauth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements BaiduOAuthApi {}

class _MockStore extends Mock implements BaiduCredentialStore {}

void main() {
  late _MockApi api;
  late _MockStore store;
  late DefaultBaiduCredentialRepository repository;

  setUpAll(() {
    registerFallbackValue(
      BaiduCredentialBundle(
        accessToken: 'fallback-access',
        refreshToken: 'fallback-refresh',
        expiresAt: DateTime.utc(2026),
        scope: 'basic,netdisk',
      ),
    );
  });

  BaiduCredentialBundle credential({
    String access = 'access',
    String refresh = 'refresh',
    DateTime? expiresAt,
  }) {
    return BaiduCredentialBundle(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt ?? DateTime.utc(2026, 7, 18, 12, 30),
      scope: 'basic,netdisk',
    );
  }

  BaiduOAuthSession session() => BaiduOAuthSession(
    sessionId: 'sid',
    pollToken: 'poll',
    authorizationUri: Uri.parse('https://openapi.baidu.com/oauth'),
    expiresAt: DateTime.utc(2026, 7, 18, 12, 10),
    pollInterval: const Duration(seconds: 2),
  );

  setUp(() {
    api = _MockApi();
    store = _MockStore();
    repository = DefaultBaiduCredentialRepository(
      api: api,
      store: store,
      clock: Clock.fixed(DateTime.utc(2026, 7, 18, 12)),
    );
  });

  group('DefaultBaiduCredentialRepository', () {
    test('主动断开清除凭据并标记下一次授权强制登录', () async {
      when(() => store.clear()).thenAnswer((_) async {});
      when(() => store.writeForceLoginOnce()).thenAnswer((_) async {});

      await repository.disconnect();

      verifyInOrder([() => store.clear(), () => store.writeForceLoginOnce()]);
    });

    test('创建会话时读取一次性标志，并在授权终态后消费', () async {
      when(() => store.readForceLoginOnce()).thenAnswer((_) async => true);
      when(
        () => api.createSession(BaiduNetdiskPlatform.android, forceLogin: true),
      ).thenAnswer((_) async => session());
      when(() => store.clearForceLoginOnce()).thenAnswer((_) async {});

      await repository.createSession(BaiduNetdiskPlatform.android);
      await repository.consumeForceLoginOnce();

      verify(
        () => api.createSession(BaiduNetdiskPlatform.android, forceLogin: true),
      ).called(1);
      verify(() => store.clearForceLoginOnce()).called(1);
    });

    test('普通清除凭据不设置强制登录标志', () async {
      when(() => store.clear()).thenAnswer((_) async {});

      await repository.clearCredential();

      verifyNever(() => store.writeForceLoginOnce());
    });

    test(
      'persistCompletedSession 先写 secure storage，成功后再 acknowledge',
      () async {
        final calls = <String>[];
        when(() => store.write(any())).thenAnswer((_) async {
          calls.add('write');
        });
        when(
          () => api.acknowledge(sessionId: 'sid', pollToken: 'poll'),
        ).thenAnswer((_) async {
          calls.add('ack');
        });

        await repository.persistCompletedSession(
          session: session(),
          credential: credential(),
        );

        expect(calls, ['write', 'ack']);
      },
    );

    test('secure storage 写入失败时不 acknowledge，保留后端临时 credential', () async {
      when(() => store.write(any())).thenThrow(Exception('disk full'));

      expect(
        repository.persistCompletedSession(
          session: session(),
          credential: credential(),
        ),
        throwsException,
      );
      verifyNever(
        () => api.acknowledge(
          sessionId: any(named: 'sessionId'),
          pollToken: any(named: 'pollToken'),
        ),
      );
    });

    test('未过期 credential 直接返回 access token，不 refresh', () async {
      when(() => store.read()).thenAnswer((_) async => credential());

      final token = await repository.getValidAccessToken();

      expect(token, 'access');
      verifyNever(() => api.refresh(refreshToken: any(named: 'refreshToken')));
    });

    test('提前 5 分钟过期时 refresh 并整体写回 bundle', () async {
      when(() => store.read()).thenAnswer(
        (_) async => credential(expiresAt: DateTime.utc(2026, 7, 18, 12, 4)),
      );
      when(() => api.refresh(refreshToken: 'refresh')).thenAnswer(
        (_) async => credential(access: 'access2', refresh: 'refresh2'),
      );
      when(() => store.write(any())).thenAnswer((_) async {});

      final token = await repository.getValidAccessToken();

      expect(token, 'access2');
      final saved = verify(() => store.write(captureAny())).captured.single;
      expect(saved, isA<BaiduCredentialBundle>());
      final savedCredential = saved as BaiduCredentialBundle;
      expect(savedCredential.refreshToken, 'refresh2');
    });

    test('并发 refresh 共享同一个 Future', () async {
      final completer = Completer<BaiduCredentialBundle>();
      when(() => store.read()).thenAnswer(
        (_) async => credential(expiresAt: DateTime.utc(2026, 7, 18, 12, 4)),
      );
      when(
        () => api.refresh(refreshToken: 'refresh'),
      ).thenAnswer((_) => completer.future);
      when(() => store.write(any())).thenAnswer((_) async {});

      final first = repository.getValidAccessToken();
      final second = repository.getValidAccessToken();
      completer.complete(credential(access: 'access2', refresh: 'refresh2'));

      expect(await first, 'access2');
      expect(await second, 'access2');
      verify(() => api.refresh(refreshToken: 'refresh')).called(1);
    });

    test('reauthorization_required 时清除 credential 并抛重新授权异常', () async {
      when(() => store.read()).thenAnswer(
        (_) async => credential(expiresAt: DateTime.utc(2026, 7, 18, 12, 4)),
      );
      when(() => api.refresh(refreshToken: 'refresh')).thenThrow(
        const BaiduNetdiskApiError(
          code: BaiduNetdiskOAuthErrorCode.reauthorizationRequired,
          message: 'reauthorize',
        ),
      );
      when(() => store.clear()).thenAnswer((_) async {});

      await expectLater(
        repository.getValidAccessToken(),
        throwsA(isA<BaiduReauthorizationRequiredException>()),
      );
      await untilCalled(() => store.clear());
    });
  });
}
