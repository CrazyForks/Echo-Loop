import 'package:echo_loop/features/subscription/models/entitlement.dart';
import 'package:echo_loop/features/subscription/models/subscription_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Entitlement.isActive', () {
    final now = DateTime.utc(2026, 6, 22, 12);

    test('非 pro 永远不活跃', () {
      expect(Entitlement.free.isActive(now), isFalse);
      const notPro = Entitlement(isPremium: false, expiresAt: null);
      expect(notPro.isActive(now), isFalse);
    });

    test('pro 且无到期时间 = 永久有效', () {
      const lifetime = Entitlement(isPremium: true);
      expect(lifetime.isActive(now), isTrue);
    });

    test('pro 且到期时间在未来 = 有效', () {
      final ent = Entitlement(
        isPremium: true,
        expiresAt: now.add(const Duration(days: 1)),
      );
      expect(ent.isActive(now), isTrue);
    });

    test('pro 但已过期 = 无效', () {
      final ent = Entitlement(
        isPremium: true,
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );
      expect(ent.isActive(now), isFalse);
    });
  });

  group('Entitlement JSON 往返', () {
    test('完整字段往返一致', () {
      final ent = Entitlement(
        isPremium: true,
        activeEntitlements: const {'pro'},
        productId: 'pro_yearly',
        period: SubscriptionPeriod.yearly,
        expiresAt: DateTime.utc(2027, 1, 1),
        willRenew: true,
      );
      final restored = Entitlement.fromJson(ent.toJson());
      expect(restored, ent);
      expect(restored.period, SubscriptionPeriod.yearly);
    });

    test('一次性购买类型往返，旧缓存缺字段回退为空', () {
      const entitlement = Entitlement(
        isPremium: true,
        purchaseType: PurchaseType.oneTime,
      );

      expect(
        Entitlement.fromJson(entitlement.toJson()).purchaseType,
        PurchaseType.oneTime,
      );
      expect(Entitlement.fromJson({'isPremium': true}).purchaseType, isNull);
    });

    test('缺字段 / 类型异常回退安全默认值，不抛异常', () {
      final restored = Entitlement.fromJson({
        'isPremium': 'not-a-bool',
        'activeEntitlements': 'not-a-list',
        'expiresAt': 12345,
        'period': 'not-a-period',
      });
      expect(restored.isPremium, isFalse);
      expect(restored.activeEntitlements, isEmpty);
      expect(restored.expiresAt, isNull);
      expect(restored.willRenew, isFalse);
      expect(restored.period, isNull);
      expect(restored.purchaseType, isNull);
    });
  });

  test('相等性按值比较（含集合无序）', () {
    const a = Entitlement(isPremium: true, activeEntitlements: {'pro', 'plus'});
    const b = Entitlement(isPremium: true, activeEntitlements: {'plus', 'pro'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
