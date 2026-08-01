/// AI 配额拒绝的统一业务语义。
library;

/// 后端拒绝本次 AI 请求的原因。
enum AiQuotaRejectionReason {
  /// 免费额度存在，但本周期已经用尽。
  exhausted,

  /// 后端通过 `quota.limit == 0` 表示免费版不开放该功能。
  unsupportedForFreePlan,
}

/// 后端 402 配额响应中与客户端提示相关的信息。
class AiQuotaRejection {
  const AiQuotaRejection({
    this.reason = AiQuotaRejectionReason.exhausted,
    this.resetAt,
  });

  final AiQuotaRejectionReason reason;
  final DateTime? resetAt;

  /// 解析 402 `quota_exceeded` 响应。
  ///
  /// 只有明确返回 `code == quota_exceeded` 且数值型 `limit == 0` 时，
  /// 才判定为免费版不支持；其余响应保持既有的额度用尽语义。
  factory AiQuotaRejection.fromResponseData(Object? data) {
    if (data is! Map) return const AiQuotaRejection();
    final quota = data['quota'];
    if (quota is! Map) return const AiQuotaRejection();

    final rawLimit = quota['limit'];
    final reason =
        data['code'] == 'quota_exceeded' && rawLimit is num && rawLimit == 0
        ? AiQuotaRejectionReason.unsupportedForFreePlan
        : AiQuotaRejectionReason.exhausted;
    final rawResetAt = quota['resetAt'];
    final resetAt = rawResetAt is String && rawResetAt.isNotEmpty
        ? DateTime.tryParse(rawResetAt)?.toUtc()
        : null;
    return AiQuotaRejection(reason: reason, resetAt: resetAt);
  }
}
