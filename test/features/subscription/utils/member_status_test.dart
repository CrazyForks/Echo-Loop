import 'package:echo_loop/features/subscription/models/entitlement.dart';
import 'package:echo_loop/features/subscription/models/subscription_plan.dart';
import 'package:echo_loop/features/subscription/utils/member_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 1);
  final future = DateTime.utc(2026, 8, 1);

  group('status 派生', () {
    test('willRenew=true → active', () {
      final s = summarizeMembership(
        Entitlement(isPremium: true, expiresAt: future, willRenew: true),
        now: now,
      );
      expect(s.status, MemberStatusKind.active);
    });

    test('willRenew=false 且有到期时间 → expiring', () {
      final s = summarizeMembership(
        Entitlement(isPremium: true, expiresAt: future, willRenew: false),
        now: now,
      );
      expect(s.status, MemberStatusKind.expiring);
    });

    test('一次性购买且有到期时间 → fixedTerm', () {
      final summary = summarizeMembership(
        Entitlement(
          isPremium: true,
          expiresAt: future,
          purchaseType: PurchaseType.oneTime,
        ),
        now: now,
      );

      expect(summary.status, MemberStatusKind.fixedTerm);
    });

    test('expiresAt=null → lifetime，且 expiresAtLocal 为 null', () {
      final s = summarizeMembership(
        const Entitlement(isPremium: true, willRenew: false),
        now: now,
      );
      expect(s.status, MemberStatusKind.lifetime);
      expect(s.expiresAtLocal, isNull);
    });

    test('expiresAtLocal 为到期时间的本地时区', () {
      final s = summarizeMembership(
        Entitlement(isPremium: true, expiresAt: future, willRenew: true),
        now: now,
      );
      expect(s.expiresAtLocal, future.toLocal());
    });
  });

  group('period 派生', () {
    test('Entitlement.period 存在时直接采用，优先于 plans 与启发式', () {
      // productId 无法启发式识别、plans 也不含，但 period 已由平台解析存入 → 直接用。
      final s = summarizeMembership(
        Entitlement(
          isPremium: true,
          productId: 'sku_opaque_123',
          period: SubscriptionPeriod.yearly,
          expiresAt: future,
          willRenew: true,
        ),
        now: now,
      );
      expect(s.period, SubscriptionPeriod.yearly);
    });

    test('plans 精确匹配优先于启发式', () {
      // productId 含 "month" 字样，但 plans 里映射为 yearly，应以 plans 为准。
      const plans = [
        SubscriptionPlan(
          planId: 'combo_month_bundle',
          title: 'Bundle',
          priceString: r'$39.99',
          period: SubscriptionPeriod.yearly,
        ),
      ];
      final s = summarizeMembership(
        Entitlement(
          isPremium: true,
          productId: 'combo_month_bundle',
          expiresAt: future,
          willRenew: true,
        ),
        now: now,
        plans: plans,
      );
      expect(s.period, SubscriptionPeriod.yearly);
    });

    test('无 plans 时字符串启发式：year/annual/month/life', () {
      SubscriptionPeriod? p(String id) => summarizeMembership(
        Entitlement(isPremium: true, productId: id, expiresAt: future),
        now: now,
      ).period;
      expect(p('pro_yearly'), SubscriptionPeriod.yearly);
      expect(p('annual_sub'), SubscriptionPeriod.yearly);
      expect(p('pro_monthly'), SubscriptionPeriod.monthly);
      expect(p('lifetime_unlock'), SubscriptionPeriod.lifetime);
    });

    test('productId 无法识别 → period 为 null', () {
      final s = summarizeMembership(
        Entitlement(isPremium: true, productId: 'sku_xyz', expiresAt: future),
        now: now,
      );
      expect(s.period, isNull);
    });

    test('productId 为 null → period 为 null', () {
      final s = summarizeMembership(
        const Entitlement(isPremium: true),
        now: now,
      );
      expect(s.period, isNull);
    });
  });
}
