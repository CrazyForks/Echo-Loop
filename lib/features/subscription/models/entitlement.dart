/// 订阅权益（Entitlement）模型。
///
/// 纯数据、不可变，不依赖任何 State 或平台类型（不引入 RevenueCat / Supabase 类型）。
/// 表示「用户当前拥有什么权益」这一事实，由后端 / RevenueCat / 本地缓存对账后得出，
/// 真相源在后端（见 SubscriptionController 对账逻辑）。
library;

import 'entitlement_source.dart';
import 'subscription_plan.dart';

/// 不可变权益快照。
class Entitlement {
  /// 是否持有付费会员权益（当前单一等级 = Plus）。
  ///
  /// 表示「付费 vs 免费」这一个维度，与买哪档（未来 Plus/Pro）、买多久（[period]）无关。
  /// 命名用 premium 泛指付费，避免与将来可能的 Pro 档位混淆。
  final bool isPremium;

  /// 已激活的权益标识集合（对应 RevenueCat entitlement identifiers）。
  final Set<String> activeEntitlements;

  /// 当前生效的订阅商品 ID（如 `pro_yearly`），无订阅时为 null。
  final String? productId;

  /// 订阅周期（月/年/终身）。来自平台 packageType（权威），无法判定时为 null。
  ///
  /// 由购买服务在映射时解析并存入（见 RevenueCatPurchaseService），会随本模型一起
  /// 序列化缓存——好处是**离线/冷启动也能显示准确套餐名**，不依赖 offering 是否已拉到。
  final SubscriptionPeriod? period;

  /// 当前代表性权益的购买类型；旧缓存或旧后端未提供时为空。
  final PurchaseType? purchaseType;

  /// 权益到期时间（UTC）。null 表示永久（如终身买断）或无订阅。
  final DateTime? expiresAt;

  /// 是否会自动续费。
  final bool willRenew;

  /// 订阅来源渠道（Apple / Google / Paddle）。
  ///
  /// 决定「管理订阅」入口指向哪个平台，与 App 当前运行平台解耦。
  /// 无有效权益、老缓存无该字段或来源不可识别时为 [EntitlementSource.unknown]，
  /// 此时管理入口回退到「按当前平台渠道」的旧逻辑。
  final EntitlementSource source;

  const Entitlement({
    required this.isPremium,
    this.activeEntitlements = const {},
    this.productId,
    this.period,
    this.purchaseType,
    this.expiresAt,
    this.willRenew = false,
    this.source = EntitlementSource.unknown,
  });

  /// 免费态（无任何权益）。
  static const Entitlement free = Entitlement(isPremium: false);

  /// 在给定时刻 [now] 是否仍然有效。
  ///
  /// 既要 [isPremium] 为真，又要未过期（无到期时间视为永久有效）。
  /// [now] 显式传入以便测试，避免内部直接读系统时钟。
  bool isActive(DateTime now) {
    if (!isPremium) return false;
    final expiry = expiresAt;
    if (expiry == null) return true;
    return expiry.isAfter(now);
  }

  Entitlement copyWith({
    bool? isPremium,
    Set<String>? activeEntitlements,
    String? productId,
    SubscriptionPeriod? period,
    PurchaseType? purchaseType,
    DateTime? expiresAt,
    bool? willRenew,
    EntitlementSource? source,
  }) {
    return Entitlement(
      isPremium: isPremium ?? this.isPremium,
      activeEntitlements: activeEntitlements ?? this.activeEntitlements,
      productId: productId ?? this.productId,
      period: period ?? this.period,
      purchaseType: purchaseType ?? this.purchaseType,
      expiresAt: expiresAt ?? this.expiresAt,
      willRenew: willRenew ?? this.willRenew,
      source: source ?? this.source,
    );
  }

  /// 序列化为 JSON（用于 secure_storage 本地缓存）。
  Map<String, dynamic> toJson() {
    return {
      'isPremium': isPremium,
      'activeEntitlements': activeEntitlements.toList(),
      'productId': productId,
      'period': period?.name,
      'purchaseType': switch (purchaseType) {
        final value? => purchaseTypeName(value),
        null => null,
      },
      'expiresAt': expiresAt?.toIso8601String(),
      'willRenew': willRenew,
      'source': source.name,
    };
  }

  /// 从 JSON 反序列化。字段缺失 / 类型异常时回退为安全默认值，
  /// 调用方（缓存层）负责捕获解析异常并回退为「未知」。
  factory Entitlement.fromJson(Map<String, dynamic> json) {
    final rawEntitlements = json['activeEntitlements'];
    final entitlements = rawEntitlements is List
        ? rawEntitlements.whereType<String>().toSet()
        : <String>{};
    final rawExpiry = json['expiresAt'];
    final rawPeriod = json['period'];
    return Entitlement(
      isPremium: json['isPremium'] == true,
      activeEntitlements: entitlements,
      productId: json['productId'] is String
          ? json['productId'] as String
          : null,
      period: rawPeriod is String ? _periodFromName(rawPeriod) : null,
      purchaseType: purchaseTypeFromName(json['purchaseType']),
      expiresAt: rawExpiry is String ? DateTime.tryParse(rawExpiry) : null,
      willRenew: json['willRenew'] == true,
      source: entitlementSourceFromName(json['source'] as String?),
    );
  }

  /// 按枚举名解析周期，未知名回退 null（旧缓存无该字段时安全）。
  static SubscriptionPeriod? _periodFromName(String name) {
    for (final p in SubscriptionPeriod.values) {
      if (p.name == name) return p;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entitlement &&
          isPremium == other.isPremium &&
          _setEquals(activeEntitlements, other.activeEntitlements) &&
          productId == other.productId &&
          period == other.period &&
          purchaseType == other.purchaseType &&
          expiresAt == other.expiresAt &&
          willRenew == other.willRenew &&
          source == other.source;

  @override
  int get hashCode => Object.hash(
    isPremium,
    Object.hashAllUnordered(activeEntitlements),
    productId,
    period,
    purchaseType,
    expiresAt,
    willRenew,
    source,
  );
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
