/// AI 免费额度提示的功能名和标题映射。
library;

import '../../../l10n/app_localizations.dart';
import '../models/ai_quota_rejection.dart';
import '../models/premium_feature.dart';

/// 返回与 [feature] 对应的本地化 AI 功能名称。
String aiQuotaFeatureName(AppLocalizations l10n, PremiumFeature feature) =>
    switch (feature) {
      PremiumFeature.aiTranslation => l10n.aiQuotaFeatureTranslation,
      PremiumFeature.aiAnalysis => l10n.aiQuotaFeatureAnalysis,
      PremiumFeature.aiSenseGroup => l10n.aiQuotaFeatureSenseGroup,
      PremiumFeature.aiWordAnalysis => l10n.aiQuotaFeatureWordAnalysis,
      PremiumFeature.aiTranscription => l10n.aiQuotaFeatureTranscription,
      PremiumFeature.aiChat => l10n.aiQuotaFeatureChat,
      PremiumFeature.aiRetellReview => l10n.aiQuotaFeatureRetellReview,
    };

/// 返回明确说明 AI 功能且按月重置的额度用尽标题。
///
/// [feature] 缺失仅用于兼容无法辨识来源的旧调用；正常产品入口都应传入具体功能。
String aiQuotaExceededTitleFor(
  AppLocalizations l10n,
  PremiumFeature? feature,
) => feature == null
    ? l10n.aiQuotaExceededGenericTitle
    : l10n.aiQuotaExceededTitle(aiQuotaFeatureName(l10n, feature));

/// 根据后端配额拒绝原因返回对应标题。
String aiQuotaTitleFor(
  AppLocalizations l10n,
  PremiumFeature? feature,
  AiQuotaRejectionReason reason,
) {
  if (reason == AiQuotaRejectionReason.exhausted) {
    return aiQuotaExceededTitleFor(l10n, feature);
  }
  return feature == null
      ? l10n.aiQuotaUnsupportedGenericTitle
      : l10n.aiQuotaUnsupportedTitle(aiQuotaFeatureName(l10n, feature));
}

/// 根据后端配额拒绝原因返回对应说明。
String aiQuotaMessageFor(
  AppLocalizations l10n,
  AiQuotaRejectionReason reason,
) => reason == AiQuotaRejectionReason.unsupportedForFreePlan
    ? l10n.aiQuotaUnsupportedMessage
    : l10n.aiQuotaExceededMessage;
