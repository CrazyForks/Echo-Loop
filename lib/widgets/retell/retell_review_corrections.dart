/// 复述评估的「表达纠错」卡与「一条建议」callout。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/retell_review_evaluation.dart';
import '../../theme/app_theme.dart';
import 'retell_review_rating_style.dart';

/// 唯一一条建议的内容块，用淡色高亮和要点/纠错卡形成层级差。
///
/// 自己不带标签和图标：身份由小节标题给（见 report 里的 `_SectionLabel`），
/// 卡内再重复一次就成了两级标题。
///
/// 用小节自己的灯泡色淡染，而不是 `secondaryContainer`：后者是一整块实色，和顶部
/// hero 的淡染不是同一套语言，在一屏近白卡片里会单独跳出来。改成淡染 + 同色细描边后，
/// 报告首尾各有一块淡色（顶部评级、底部建议），中间全是近白卡，层级才读得出来。
class RetellReviewSuggestionCallout extends StatelessWidget {
  final String text;

  const RetellReviewSuggestionCallout({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = retellSuggestionSectionVisual(context).color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? .13 : .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .20)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.5,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 表达纠错：「类别标签 → 原句 → 更正（成功色）→ 说明」四层对照。
///
/// 原句是否划掉由类别决定（见 [retellCorrectionTypeVisual]）：只有说错了的
/// 语法和用词才划掉，冗余/说法/衔接的原句本身不算错。
class RetellReviewCorrectionCard extends StatelessWidget {
  final RetellReviewCorrection correction;

  const RetellReviewCorrectionCard({required this.correction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final typeVisual = retellCorrectionTypeVisual(
      context,
      l10n,
      correction.type,
    );
    final correctionColor = retellCorrectionColor(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.s + 2),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: retellCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类别尚未到达时不占位，避免流式过程中标签闪现。
          if (typeVisual.label.isNotEmpty) ...[
            _CorrectionTypeChip(visual: typeVisual),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(
            correction.transcript,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
              color: typeVisual.color,
              decoration: typeVisual.strikeThrough
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationColor: typeVisual.color.withValues(alpha: .6),
            ),
          ),
          if (correction.correction.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: correctionColor,
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    correction.correction,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: correctionColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (correction.explanation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              correction.explanation,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 纠错类别标签，用类别色淡染的小胶囊。
class _CorrectionTypeChip extends StatelessWidget {
  final RetellCorrectionTypeVisual visual;

  const _CorrectionTypeChip({required this.visual});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s,
      vertical: AppSpacing.xs - 1,
    ),
    decoration: BoxDecoration(
      color: visual.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      visual.label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: visual.color,
      ),
    ),
  );
}
