import 'dart:async';

import 'package:echo_loop/features/subscription/models/entitlement.dart';
import 'package:echo_loop/features/subscription/models/subscription_plan.dart';
import 'package:echo_loop/features/subscription/providers/subscription_identity.dart';
import 'package:echo_loop/features/subscription/screens/subscription_debug_screen.dart';
import 'package:echo_loop/features/subscription/services/entitlement_cache.dart';
import 'package:echo_loop/features/subscription/services/entitlement_repository.dart';
import 'package:echo_loop/features/subscription/services/purchase_service.dart';
import 'package:echo_loop/features/subscription/services/revenuecat_purchase_service.dart'
    show purchaseServiceProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 返回固定权益与诊断快照的购买服务替身。
class _FakePurchaseService implements PurchaseService {
  _FakePurchaseService(this.current);
  final Entitlement current;
  int invalidateCalls = 0;

  @override
  Future<List<SubscriptionPlan>> fetchPlans({
    bool includeIntroEligibility = true,
    bool force = false,
  }) async => const [];
  @override
  Future<Entitlement> currentEntitlement() async => current;
  @override
  Stream<Entitlement> get entitlementStream => const Stream.empty();
  @override
  Future<Entitlement> purchase(String planId) async => current;
  @override
  Future<RestorePurchaseResult> restore() async =>
      RestorePurchaseResult(entitlement: current);
  @override
  Future<void> identify(String? userId) async {}
  @override
  Future<bool> ensureIdentified(String userId) async => true;
  @override
  Future<void> invalidateCustomerInfoCache() async => invalidateCalls++;
  @override
  Future<Map<String, Object?>> debugCustomerInfoSnapshot() async => {
    'lookForEntitlementId': 'Echo Loop Plus',
    'activeEntitlements': current.isPremium ? ['Echo Loop Plus'] : <String>[],
  };
  @override
  Future<String?> storefrontCountryCode() async => null;
}

class _FakeRepo implements EntitlementRepository {
  _FakeRepo([this.result]);
  final Entitlement? result;

  @override
  Future<Entitlement?> fetchRemote({
    required String userId,
    required String accessToken,
    bool force = false,
  }) async => result;
}

/// 内存缓存替身（避免 widget 测试触发 FlutterSecureStorage 平台缺失异常）。
class _MemCache extends EntitlementCache {
  CachedEntitlement? _stored;
  @override
  Future<CachedEntitlement?> read() async => _stored;
  @override
  Future<void> write(CachedEntitlement cached) async => _stored = cached;
  @override
  Future<void> clear() async => _stored = null;
}

Widget _wrap(PurchaseService purchases, {Entitlement? backendEntitlement}) {
  return ProviderScope(
    overrides: [
      purchaseServiceProvider.overrideWithValue(purchases),
      entitlementRepositoryProvider.overrideWithValue(
        _FakeRepo(backendEntitlement),
      ),
      entitlementCacheProvider.overrideWithValue(_MemCache()),
      // 单一来源下匿名恒为 free：要展示后端权益需以登录身份对账。
      subscriptionIdentityProvider.overrideWithValue(
        backendEntitlement == null
            ? SubscriptionIdentity.anonymous
            : const SubscriptionIdentity(userId: 'u1', accessToken: 't1'),
      ),
    ],
    child: const MaterialApp(home: SubscriptionDebugScreen()),
  );
}

void main() {
  testWidgets('free 态：渲染各卡片与操作项', (tester) async {
    await tester.pumpWidget(_wrap(_FakePurchaseService(Entitlement.free)));
    await tester.pumpAndSettle();

    expect(find.text('当前权益（App 真相源）'), findsOneWidget);
    expect(find.text('RevenueCat 原始 CustomerInfo'), findsOneWidget);
    expect(find.text('清本地缓存 + 失效 RC 缓存 + 强刷'), findsOneWidget);
    expect(find.text('恢复购买'), findsOneWidget);
    expect(find.text('free'), findsWidgets);
  });

  testWidgets('点「清缓存并强刷」触发 invalidateCustomerInfoCache', (tester) async {
    final purchases = _FakePurchaseService(Entitlement.free);
    await tester.pumpWidget(_wrap(purchases));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清本地缓存 + 失效 RC 缓存 + 强刷'));
    await tester.pumpAndSettle();

    expect(purchases.invalidateCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('pro 态：当前权益显示 isActive=true', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakePurchaseService(const Entitlement(isPremium: true)),
        backendEntitlement: const Entitlement(isPremium: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('premium'), findsWidgets);
    expect(find.text('true'), findsWidgets);
  });
}
