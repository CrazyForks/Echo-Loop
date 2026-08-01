/// AI 免费额度用尽的统一确认弹窗。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../models/ai_quota_rejection.dart';
import '../models/premium_feature.dart';
import '../providers/ai_quota_limit_provider.dart';
import '../providers/subscription_identity.dart';
import '../utils/ai_quota_copy.dart';
import 'feature_gate.dart' show openPaywall;

/// 展示 AI 额度用尽说明，并仅在用户确认后进入订阅页。
///
/// 当 [respectReminderCooldown] 为 true 且该功能仍处于提醒冷却期时，不显示弹窗。
/// 用户主动触发功能时应传 false，确保每次操作都有明确反馈。无法确定具体功能的
/// 本地门禁可传入 null，此时仍展示弹窗，但不写入按用户维度的提醒记录。调用方负责
/// 防止同一时刻重复展示。
Future<void> showAiQuotaExceededDialog({
  required BuildContext context,
  required WidgetRef ref,
  PremiumFeature? feature,
  AiQuotaRejectionReason reason = AiQuotaRejectionReason.exhausted,
  bool respectReminderCooldown = false,
}) async {
  final userId = ref.read(subscriptionIdentityProvider).userId;
  final store = ref.read(aiQuotaLimitStoreProvider);
  if (respectReminderCooldown &&
      userId != null &&
      feature != null &&
      !store.shouldShowReminder(userId, feature)) {
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        aiQuotaTitleFor(l10n, feature, reason),
        style: Theme.of(dialogContext).textTheme.titleLarge,
      ),
      content: Text(aiQuotaMessageFor(l10n, reason)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop('dismiss'),
          child: Text(l10n.aiQuotaExceededDismiss),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop('subscribe'),
          child: Text(l10n.aiQuotaExceededSubscribe),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (userId != null && feature != null) {
    await store.markReminderShown(userId, feature);
  }
  if (result == 'subscribe' && context.mounted) {
    await openPaywall(context, ref);
  }
}
