/// Supabase access token 的统一有效性协调器。
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_logger.dart';

/// Token Gate 可区分的失败原因。
enum TokenGateFailure { notSignedIn, identityChanged, temporarilyUnavailable }

/// Token Gate 失败；业务层可据此区分重新登录与临时重试。
class TokenGateException implements Exception {
  const TokenGateException(this.reason, [this.cause]);

  final TokenGateFailure reason;
  final Object? cause;

  @override
  String toString() => 'TokenGateException(${reason.name})';
}

/// 不含 refresh token 的最小 session 快照。
class AuthSessionSnapshot {
  const AuthSessionSnapshot({
    required this.userId,
    required this.accessToken,
    required this.expiresAt,
  });

  final String userId;
  final String accessToken;
  final DateTime? expiresAt;
}

/// 会改变登录身份代际的认证事件。
enum AuthSessionEvent { signedIn, signedOut, identityReplaced, tokenRefreshed }

/// Coordinator 对认证 SDK 的最小依赖，便于纯 Dart 测试竞态。
abstract interface class AuthSessionSource {
  AuthSessionSnapshot? get currentSession;
  Stream<AuthSessionEvent> get onAuthStateChange;
  Future<void> refreshSession();
}

/// [GoTrueClient] 到 Token Gate 的生产适配器。
class SupabaseAuthSessionSource implements AuthSessionSource {
  SupabaseAuthSessionSource(this._auth);

  final GoTrueClient _auth;

  @override
  AuthSessionSnapshot? get currentSession => _snapshot(_auth.currentSession);

  @override
  Stream<AuthSessionEvent> get onAuthStateChange => _auth.onAuthStateChange.map(
    (state) => switch (state.event) {
      AuthChangeEvent.tokenRefreshed => AuthSessionEvent.tokenRefreshed,
      AuthChangeEvent.initialSession ||
      AuthChangeEvent.userUpdated ||
      AuthChangeEvent.mfaChallengeVerified => AuthSessionEvent.tokenRefreshed,
      AuthChangeEvent.signedOut => AuthSessionEvent.signedOut,
      AuthChangeEvent.signedIn => AuthSessionEvent.signedIn,
      _ => AuthSessionEvent.identityReplaced,
    },
  );

  @override
  Future<void> refreshSession() async {
    await _auth.refreshSession();
  }

  AuthSessionSnapshot? _snapshot(Session? session) {
    if (session == null) return null;
    final expiresAtSeconds = session.expiresAt;
    return AuthSessionSnapshot(
      userId: session.user.id,
      accessToken: session.accessToken,
      expiresAt: expiresAtSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              expiresAtSeconds * 1000,
              isUtc: true,
            ),
    );
  }
}

/// 为所有需要 Supabase 登录的自建后端请求提供最新有效 access token。
class SupabaseTokenCoordinator {
  SupabaseTokenCoordinator(
    this._source, {
    DateTime Function()? now,
    this.expirySafetyWindow = const Duration(seconds: 60),
    this.refreshWaitTimeout = const Duration(seconds: 15),
  }) : _now = now ?? DateTime.now {
    _authSubscription = _source.onAuthStateChange.listen(_onAuthEvent);
  }

  final AuthSessionSource _source;
  final DateTime Function() _now;
  final Duration expirySafetyWindow;
  final Duration refreshWaitTimeout;
  late final StreamSubscription<AuthSessionEvent> _authSubscription;
  Future<void>? _refreshInFlight;
  int _identityGeneration = 0;
  bool _disposed = false;

  /// 返回有效 token；过期时所有调用方共享一次刷新，不进行轮询。
  Future<String> requireValidAccessToken({bool forceRefresh = false}) async {
    final before = _source.currentSession;
    if (before == null) {
      AppLogger.log(
        'AuthToken',
        'Token Gate 拒绝: reason=notSignedIn force=$forceRefresh '
            'generation=$_identityGeneration',
      );
      throw const TokenGateException(TokenGateFailure.notSignedIn);
    }
    final generation = _identityGeneration;
    if (!forceRefresh && _isUsable(before)) {
      AppLogger.log(
        'AuthToken',
        'Token Gate 放行: source=currentSession generation=$generation '
            'expiresIn=${before.expiresAt?.difference(_now()).inSeconds}s',
      );
      return before.accessToken;
    }

    final existingRefresh = _refreshInFlight;
    final refresh = existingRefresh ?? _runRefresh();
    _refreshInFlight = refresh;
    AppLogger.log(
      'AuthToken',
      'Token Gate 等待刷新: generation=$generation force=$forceRefresh '
          'shared=${existingRefresh != null} '
          'sessionUsable=${_isUsable(before)}',
    );
    try {
      await refresh.timeout(refreshWaitTimeout);
    } on TimeoutException catch (error) {
      AppLogger.log(
        'AuthToken',
        'Token Gate 刷新失败: reason=timeout generation=$generation '
            'timeoutSeconds=${refreshWaitTimeout.inSeconds}',
      );
      throw TokenGateException(TokenGateFailure.temporarilyUnavailable, error);
    } on AuthException catch (error) {
      final sessionCleared = _source.currentSession == null;
      AppLogger.log(
        'AuthToken',
        'Token Gate 刷新失败: reason=authException generation=$generation '
            'sessionCleared=$sessionCleared',
      );
      if (sessionCleared) {
        throw TokenGateException(TokenGateFailure.notSignedIn, error);
      }
      throw TokenGateException(TokenGateFailure.temporarilyUnavailable, error);
    } catch (error) {
      AppLogger.log(
        'AuthToken',
        'Token Gate 刷新失败: reason=temporary generation=$generation '
            'type=${error.runtimeType}',
      );
      throw TokenGateException(TokenGateFailure.temporarilyUnavailable, error);
    }

    final after = _source.currentSession;
    if (_disposed ||
        generation != _identityGeneration ||
        after == null ||
        after.userId != before.userId) {
      AppLogger.log(
        'AuthToken',
        'Token Gate 丢弃刷新结果: reason=identityChanged '
            'beforeGeneration=$generation currentGeneration=$_identityGeneration '
            'disposed=$_disposed hasSession=${after != null}',
      );
      throw const TokenGateException(TokenGateFailure.identityChanged);
    }
    if (!_isUsable(after)) {
      AppLogger.log(
        'AuthToken',
        'Token Gate 拒绝刷新结果: reason=tokenStillInvalid '
            'generation=$generation hasToken=${after.accessToken.isNotEmpty} '
            'hasExpiry=${after.expiresAt != null}',
      );
      throw const TokenGateException(TokenGateFailure.notSignedIn);
    }
    AppLogger.log(
      'AuthToken',
      'Token Gate 放行: source=refreshed generation=$generation '
          'expiresIn=${after.expiresAt?.difference(_now()).inSeconds}s',
    );
    return after.accessToken;
  }

  bool _isUsable(AuthSessionSnapshot session) {
    if (session.accessToken.isEmpty) return false;
    final expiresAt = session.expiresAt;
    // Supabase access token 必须是带 exp 的 JWT；无法确认到期时间时 fail closed。
    if (expiresAt == null) return false;
    return expiresAt.isAfter(_now().add(expirySafetyWindow));
  }

  Future<void> _runRefresh() async {
    try {
      AppLogger.log('AuthToken', 'token 刷新开始: generation=$_identityGeneration');
      await _source.refreshSession();
      AppLogger.log('AuthToken', 'token 刷新完成: generation=$_identityGeneration');
    } finally {
      _refreshInFlight = null;
    }
  }

  void _onAuthEvent(AuthSessionEvent event) {
    if (event == AuthSessionEvent.tokenRefreshed) return;
    _identityGeneration++;
    AppLogger.log(
      'AuthToken',
      '认证身份变化: event=${event.name} generation=$_identityGeneration',
    );
  }

  /// 解除认证事件监听；已发出的异步结果会因 disposed 被丢弃。
  void dispose() {
    _disposed = true;
    _identityGeneration++;
    AppLogger.log(
      'AuthToken',
      'Token Coordinator 销毁: generation=$_identityGeneration',
    );
    unawaited(_authSubscription.cancel());
  }
}
