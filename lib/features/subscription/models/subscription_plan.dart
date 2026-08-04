/// 订阅套餐展示 DTO。
///
/// 这是 Paywall UI 唯一依赖的套餐数据结构，**刻意不暴露 RevenueCat 的
/// Offering / Package / StoreProduct 类型**。RevenueCat 实现（Phase 2）负责把
/// RC 的商品模型映射成本 DTO，从而把定价展示层与第三方 SDK 隔离，
/// 降低未来迁移成本（critic warning）。
library;

/// 套餐的购买类型。
enum PurchaseType {
  /// 自动续费订阅。
  subscription,

  /// 一次性付款，不会自动续费。
  oneTime,
}

/// 解析后端与本地缓存中的购买类型；未知值安全回退为空。
PurchaseType? purchaseTypeFromName(Object? value) => switch (value) {
  'subscription' => PurchaseType.subscription,
  'one_time' || 'oneTime' => PurchaseType.oneTime,
  _ => null,
};

/// 转为后端统一使用的 snake_case 名称。
String purchaseTypeName(PurchaseType type) => switch (type) {
  PurchaseType.subscription => 'subscription',
  PurchaseType.oneTime => 'one_time',
};

/// 订阅周期。
enum SubscriptionPeriod {
  /// 月订。
  monthly,

  /// 年订（主推）。
  yearly,

  /// 终身买断（一次性，P1）。
  lifetime,
}

/// 促销价格周期。
enum SubscriptionOfferPeriod {
  /// 天。
  day,

  /// 周。
  week,

  /// 月。
  month,

  /// 年。
  year,

  /// 未知周期。
  unknown,
}

/// 从商品 ID 字符串**启发式**推断订阅周期，判不出返回 null。
///
/// 仅作兜底：周期的权威来源是平台的 packageType（购买时可得），已解析出的周期会存进
/// [Entitlement.period]。本函数用于两处退化场景——① 商品 ID 未在当前 offering 里
/// （拿不到 packageType）；② 会员态离线且无缓存周期。命名不规范的商品 ID（如 `p1y`）
/// 可能判不出，返回 null 由 UI 显示兜底文案。
SubscriptionPeriod? subscriptionPeriodFromProductId(String? productId) {
  if (productId == null || productId.isEmpty) return null;
  final id = productId.toLowerCase();
  if (id.contains('year') || id.contains('annual')) {
    return SubscriptionPeriod.yearly;
  }
  if (id.contains('month')) return SubscriptionPeriod.monthly;
  if (id.contains('life')) return SubscriptionPeriod.lifetime;
  return null;
}

/// 单个可购买套餐的展示信息。
class SubscriptionPlan {
  /// 套餐标识（映射到平台商品 ID / RC package）。
  final String planId;

  /// 展示标题（如「年度会员」）。
  final String title;

  /// 本地化价格字符串（含币种符号，**必须来自平台 SDK，禁止硬编码**）。
  final String priceString;

  /// 订阅周期。
  final SubscriptionPeriod period;

  /// 购买类型；原生商店和旧调用方默认都是自动续费订阅。
  final PurchaseType purchaseType;

  /// 是否提供免费试用。
  final bool hasFreeTrial;

  /// 免费试用天数（[hasFreeTrial] 为 false 时为 0）。
  final int trialDays;

  /// 平台配置的 intro offer（免费试用 / 折扣），为空表示当前用户不应看到优惠价。
  final SubscriptionIntroOffer? introOffer;

  const SubscriptionPlan({
    required this.planId,
    required this.title,
    required this.priceString,
    required this.period,
    this.purchaseType = PurchaseType.subscription,
    this.hasFreeTrial = false,
    this.trialDays = 0,
    this.introOffer,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionPlan &&
          planId == other.planId &&
          title == other.title &&
          priceString == other.priceString &&
          period == other.period &&
          purchaseType == other.purchaseType &&
          hasFreeTrial == other.hasFreeTrial &&
          trialDays == other.trialDays &&
          introOffer == other.introOffer;

  @override
  int get hashCode => Object.hash(
    planId,
    title,
    priceString,
    period,
    purchaseType,
    hasFreeTrial,
    trialDays,
    introOffer,
  );
}

/// 单个套餐的 intro offer 展示信息。
class SubscriptionIntroOffer {
  /// Intro offer 优惠价（本地化价格字符串）；免费试用时通常为 `$0.00`。
  final String priceString;

  /// 促销周期单位。
  final SubscriptionOfferPeriod period;

  /// 促销周期单位数量，例如 `1 year` / `3 months`。
  final int periodNumberOfUnits;

  /// 促销周期重复次数。
  final int cycles;

  /// 是否为免费试用。
  final bool isFreeTrial;

  /// 促销结束后的续费价（本地化价格字符串）。
  final String renewalPriceString;

  const SubscriptionIntroOffer({
    required this.priceString,
    required this.period,
    required this.periodNumberOfUnits,
    required this.cycles,
    required this.isFreeTrial,
    required this.renewalPriceString,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionIntroOffer &&
          priceString == other.priceString &&
          period == other.period &&
          periodNumberOfUnits == other.periodNumberOfUnits &&
          cycles == other.cycles &&
          isFreeTrial == other.isFreeTrial &&
          renewalPriceString == other.renewalPriceString;

  @override
  int get hashCode => Object.hash(
    priceString,
    period,
    periodNumberOfUnits,
    cycles,
    isFreeTrial,
    renewalPriceString,
  );
}
