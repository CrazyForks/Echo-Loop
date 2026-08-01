import 'dart:async';

import 'package:echo_loop/services/supabase_token_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSessionSource implements AuthSessionSource {
  AuthSessionSnapshot? snapshot;
  final events = StreamController<AuthSessionEvent>.broadcast();
  final refreshCompleter = Completer<void>();
  int refreshCalls = 0;

  @override
  AuthSessionSnapshot? get currentSession => snapshot;

  @override
  Stream<AuthSessionEvent> get onAuthStateChange => events.stream;

  @override
  Future<void> refreshSession() {
    refreshCalls++;
    return refreshCompleter.future;
  }

  Future<void> close() => events.close();
}

void main() {
  late _FakeSessionSource source;
  late SupabaseTokenCoordinator coordinator;

  setUp(() {
    source = _FakeSessionSource();
    coordinator = SupabaseTokenCoordinator(
      source,
      now: () => DateTime.utc(2026, 8, 2),
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await source.close();
  });

  test('有效 token 直接返回且不刷新', () async {
    source.snapshot = AuthSessionSnapshot(
      userId: 'u1',
      accessToken: 'valid',
      expiresAt: DateTime.utc(2026, 8, 2, 0, 5),
    );

    expect(await coordinator.requireValidAccessToken(), 'valid');
    expect(source.refreshCalls, 0);
  });

  test('过期 token 并发请求共享刷新并重新读取 currentSession', () async {
    source.snapshot = AuthSessionSnapshot(
      userId: 'u1',
      accessToken: 'expired',
      expiresAt: DateTime.utc(2026, 8, 1),
    );

    final first = coordinator.requireValidAccessToken();
    final second = coordinator.requireValidAccessToken();
    await Future<void>.delayed(Duration.zero);
    expect(source.refreshCalls, 1);

    source.snapshot = AuthSessionSnapshot(
      userId: 'u1',
      accessToken: 'fresh',
      expiresAt: DateTime.utc(2026, 8, 2, 0, 5),
    );
    source.refreshCompleter.complete();

    expect(await first, 'fresh');
    expect(await second, 'fresh');
  });

  test('刷新期间切号会作废旧请求', () async {
    source.snapshot = AuthSessionSnapshot(
      userId: 'u1',
      accessToken: 'expired',
      expiresAt: DateTime.utc(2026, 8, 1),
    );
    final request = coordinator.requireValidAccessToken();
    await Future<void>.delayed(Duration.zero);

    source.snapshot = AuthSessionSnapshot(
      userId: 'u2',
      accessToken: 'other',
      expiresAt: DateTime.utc(2026, 8, 2, 0, 5),
    );
    source.events.add(AuthSessionEvent.signedIn);
    source.refreshCompleter.complete();

    await expectLater(
      request,
      throwsA(
        isA<TokenGateException>().having(
          (error) => error.reason,
          'reason',
          TokenGateFailure.identityChanged,
        ),
      ),
    );
  });

  test('无 session 时不刷新也不发送业务请求', () async {
    await expectLater(
      coordinator.requireValidAccessToken(),
      throwsA(
        isA<TokenGateException>().having(
          (error) => error.reason,
          'reason',
          TokenGateFailure.notSignedIn,
        ),
      ),
    );
    expect(source.refreshCalls, 0);
  });
}
