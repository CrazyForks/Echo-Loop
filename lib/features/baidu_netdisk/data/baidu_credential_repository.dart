/// 百度 credential 仓库。
///
/// 该仓库负责 OAuth 后端会话、secure storage 写入顺序、refresh single-flight
/// 与失效清理。Controller 后续只需要依赖这个抽象获取可用 access token。
library;

import 'package:clock/clock.dart';

import '../models/baidu_credential_bundle.dart';
import '../models/baidu_netdisk_error.dart';
import '../models/baidu_oauth_session.dart';
import '../models/baidu_oauth_session_status.dart';
import 'baidu_credential_store.dart';
import 'baidu_oauth_api.dart';

/// refresh token 不可用，需要用户重新授权。
class BaiduReauthorizationRequiredException implements Exception {
  /// 构造重新授权异常。
  const BaiduReauthorizationRequiredException();

  @override
  String toString() => 'BaiduReauthorizationRequiredException';
}

/// 百度凭证仓库抽象。
abstract interface class BaiduCredentialRepository {
  /// 创建 OAuth 会话。
  Future<BaiduOAuthSession> createSession(BaiduNetdiskPlatform platform);

  /// 消费本次 OAuth 已完成或已取消的一次性强制登录标志。
  Future<void> consumeForceLoginOnce();

  /// 查询 OAuth 状态。
  Future<BaiduOAuthSessionStatus> fetchStatus(BaiduOAuthSession session);

  /// 保存 completed credential，成功写入 secure storage 后再 acknowledge 后端。
  Future<void> persistCompletedSession({
    required BaiduOAuthSession session,
    required BaiduCredentialBundle credential,
  });

  /// 返回可用 access token；必要时 refresh。
  Future<String?> getValidAccessToken();

  /// 清除本地凭证。
  Future<void> clearCredential();

  /// 断开用户主动退出的百度网盘连接，并标记下一次授权强制登录。
  Future<void> disconnect();
}

/// 默认百度凭证仓库实现。
class DefaultBaiduCredentialRepository implements BaiduCredentialRepository {
  /// 构造仓库。
  DefaultBaiduCredentialRepository({
    required BaiduOAuthApi api,
    required BaiduCredentialStore store,
    Clock? clock,
  }) : _api = api,
       _store = store,
       _clock = clock ?? const Clock();

  final BaiduOAuthApi _api;
  final BaiduCredentialStore _store;
  final Clock _clock;

  Future<BaiduCredentialBundle>? _refreshInFlight;

  @override
  Future<BaiduOAuthSession> createSession(BaiduNetdiskPlatform platform) async {
    return _api.createSession(
      platform,
      forceLogin: await _store.readForceLoginOnce(),
    );
  }

  @override
  Future<void> consumeForceLoginOnce() {
    return _store.clearForceLoginOnce();
  }

  @override
  Future<BaiduOAuthSessionStatus> fetchStatus(BaiduOAuthSession session) {
    return _api.fetchStatus(
      sessionId: session.sessionId,
      pollToken: session.pollToken,
    );
  }

  @override
  Future<void> persistCompletedSession({
    required BaiduOAuthSession session,
    required BaiduCredentialBundle credential,
  }) async {
    await _store.write(credential);
    await _api.acknowledge(
      sessionId: session.sessionId,
      pollToken: session.pollToken,
    );
  }

  @override
  Future<String?> getValidAccessToken() async {
    final credential = await _store.read();
    if (credential == null) return null;
    if (credential.isAccessTokenUsable(_clock.now())) {
      return credential.accessToken;
    }
    final refreshed = await _refreshSingleFlight(credential.refreshToken);
    return refreshed.accessToken;
  }

  @override
  Future<void> clearCredential() async {
    await _store.clear();
  }

  @override
  Future<void> disconnect() async {
    await _store.clear();
    await _store.writeForceLoginOnce();
  }

  Future<BaiduCredentialBundle> _refreshSingleFlight(String refreshToken) {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _refreshCredential(refreshToken);
    _refreshInFlight = future;
    future.then(
      (_) => _clearRefreshFuture(future),
      onError: (_, _) => _clearRefreshFuture(future),
    );
    return future;
  }

  void _clearRefreshFuture(Future<BaiduCredentialBundle> future) {
    if (identical(_refreshInFlight, future)) {
      _refreshInFlight = null;
    }
  }

  Future<BaiduCredentialBundle> _refreshCredential(String refreshToken) async {
    try {
      final refreshed = await _api.refresh(refreshToken: refreshToken);
      await _store.write(refreshed);
      return refreshed;
    } on BaiduNetdiskApiError catch (error) {
      if (error.code == BaiduNetdiskOAuthErrorCode.reauthorizationRequired) {
        await _store.clear();
        throw const BaiduReauthorizationRequiredException();
      }
      rethrow;
    }
  }
}
