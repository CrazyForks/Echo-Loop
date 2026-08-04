/// 会员摘要派生（纯函数，无副作用，可单测）。
///
/// 会员态 Paywall 需要展示「当前套餐」（订阅周期）与「订阅状态」（有效 / 即将到期 /
/// 永久）。这两项由已有的 [Entitlement] 字段（productId / expiresAt / willRenew）派生，
/// 不依赖 UI、平台或 State。当前为单一会员等级，不存在 Plus/Pro 分级，故「套餐」即周期。
library;

import '../models/entitlement.dart';
import '../models/subscription_plan.dart';

/// 会员订阅状态种类。
enum MemberStatusKind {
  /// 有效且会自动续订。
  active,

  /// 有效但不再续订，将于 [MemberSummary.expiresAtLocal] 到期。
  expiring,

  /// 一次性购买的固定期限权益，不会自动续费。
  fixedTerm,

  /// 永久有效（终身买断，无到期时间）。
  lifetime,
}

/// 会员摘要：供会员态 UI 展示的派生结果。
class MemberSummary {
  /// 当前套餐对应的订阅周期；无法从 productId 判定时为 null（UI 用兜底文案）。
  final SubscriptionPeriod? period;

  /// 订阅状态。
  final MemberStatusKind status;

  /// 到期时间（已转本地时区）；[MemberStatusKind.lifetime] 时为 null。
  final DateTime? expiresAtLocal;

  const MemberSummary({
    required this.period,
    required this.status,
    required this.expiresAtLocal,
  });
}

/// 从 [e] 派生会员摘要。
///
/// - period：优先用权益自带的 [Entitlement.period]（购买时由平台 packageType 解析、
///   已随缓存持久化，最准且离线可用）；为空再用 [plans] 精确匹配 productId；仍不中
///   退回商品 ID 字符串启发式；都判不出返回 null。
/// - status：无到期时间视作永久（[MemberStatusKind.lifetime]）；否则据 [Entitlement.willRenew]
///   区分 [MemberStatusKind.active]（续订中）与 [MemberStatusKind.expiring]（不再续订）。
/// - [now] 显式传入以便测试（保留参数以对齐 [Entitlement.isActive] 的可测风格）。
MemberSummary summarizeMembership(
  Entitlement e, {
  required DateTime now,
  List<SubscriptionPlan> plans = const [],
}) {
  final expiresAtLocal = e.expiresAt?.toLocal();
  final MemberStatusKind status;
  if (e.expiresAt == null) {
    status = MemberStatusKind.lifetime;
  } else if (e.purchaseType == PurchaseType.oneTime) {
    status = MemberStatusKind.fixedTerm;
  } else {
    status = e.willRenew ? MemberStatusKind.active : MemberStatusKind.expiring;
  }
  return MemberSummary(
    period: e.period ?? _resolvePeriod(e.productId, plans),
    status: status,
    expiresAtLocal: expiresAtLocal,
  );
}

/// 由 productId 解析订阅周期：先精确匹配套餐列表，再退回字符串启发式。
SubscriptionPeriod? _resolvePeriod(
  String? productId,
  List<SubscriptionPlan> plans,
) {
  if (productId == null || productId.isEmpty) return null;
  for (final plan in plans) {
    if (plan.planId == productId) return plan.period;
  }
  return subscriptionPeriodFromProductId(productId);
}
