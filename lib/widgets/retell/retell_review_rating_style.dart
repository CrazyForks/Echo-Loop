/// 复述 AI 评估结果的视觉映射。
///
/// 把服务端的冷 token（`rating` / `keyPoints[].status`）翻译成一套配色、图标和
/// 用户可见文案。集中在这里是为了让弹窗组件只管布局，不夹带色值判断。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/retell_review_evaluation.dart';
import '../../theme/app_theme.dart';

/// 评级在 Hero 区的完整视觉描述。
class RetellRatingVisual {
  /// 强调色：评级文字、图标、已填充的档位块。
  final Color accent;

  /// Hero 容器底色（强调色淡染）。
  final Color container;

  /// 档位（1..5）；评级未到达时为 0，五档全暗。
  final int level;

  final IconData icon;

  /// 用户可见文案；评级未到达时是「正在评估…」。
  final String label;

  const RetellRatingVisual({
    required this.accent,
    required this.container,
    required this.level,
    required this.icon,
    required this.label,
  });
}

/// 档位总数，对应服务端 5 级评级。
const retellRatingLevelCount = 5;

/// 评级色板：浅色取饱和度较高的深色档保证白底可读，深色主题整体提亮一档。
const _poorLight = Color(0xFFC62828);
const _poorDark = Color(0xFFEF5350);
const _fairLight = Color(0xFFE07A2F);
const _fairDark = Color(0xFFF2A25C);
const _goodLight = AppTheme.seedColor;
const _goodDark = AppTheme.navActiveColor;
const _excellentLight = Color(0xFF00897B);
const _excellentDark = Color(0xFF4DB6AC);
const _perfectLight = AppTheme.successColor;
const _perfectDark = Color(0xFF66BB6A);

/// 生成当前评级的视觉描述。
///
/// [rating] 为 null 表示流式过程中评级尚未到达，返回中性的「正在评估」态，
/// 避免先渲染出一个会被推翻的评级词。
RetellRatingVisual retellRatingVisual(
  BuildContext context,
  AppLocalizations l10n,
  RetellReviewRating? rating,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final accent = switch (rating) {
    null => theme.colorScheme.outline,
    RetellReviewRating.poor => isDark ? _poorDark : _poorLight,
    RetellReviewRating.fair => isDark ? _fairDark : _fairLight,
    RetellReviewRating.good => isDark ? _goodDark : _goodLight,
    RetellReviewRating.excellent => isDark ? _excellentDark : _excellentLight,
    RetellReviewRating.perfect => isDark ? _perfectDark : _perfectLight,
  };
  return RetellRatingVisual(
    accent: accent,
    container: accent.withValues(alpha: isDark ? .14 : .09),
    level: switch (rating) {
      null => 0,
      RetellReviewRating.poor => 1,
      RetellReviewRating.fair => 2,
      RetellReviewRating.good => 3,
      RetellReviewRating.excellent => 4,
      RetellReviewRating.perfect => 5,
    },
    icon: switch (rating) {
      null => Icons.auto_awesome_rounded,
      RetellReviewRating.poor => Icons.flag_rounded,
      RetellReviewRating.fair => Icons.trending_up_rounded,
      RetellReviewRating.good => Icons.thumb_up_rounded,
      RetellReviewRating.excellent => Icons.star_rounded,
      RetellReviewRating.perfect => Icons.workspace_premium_rounded,
    },
    label: switch (rating) {
      // 服务端 token 是冷的（poor），面向用户仍用鼓励式文案。
      null => l10n.retellAiReviewEvaluating,
      RetellReviewRating.poor => l10n.listenAndRepeatRatingKeepGoing,
      RetellReviewRating.fair => l10n.listenAndRepeatRatingFair,
      RetellReviewRating.good => l10n.listenAndRepeatRatingGood,
      RetellReviewRating.excellent => l10n.listenAndRepeatRatingExcellent,
      RetellReviewRating.perfect => l10n.listenAndRepeatRatingPerfect,
    },
  );
}

/// 单条要点还原状态的视觉描述。
class RetellKeyPointVisual {
  final Color color;
  final IconData icon;
  final String label;

  const RetellKeyPointVisual({
    required this.color,
    required this.icon,
    required this.label,
  });
}

/// 生成要点状态的视觉描述。
///
/// [status] 为 null 表示该条要点的状态字段尚未到达（增量协议下文本先于状态送达），
/// 用中性的省略号图标占位。
RetellKeyPointVisual retellKeyPointVisual(
  BuildContext context,
  AppLocalizations l10n,
  RetellReviewKeyPointStatus? status,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return switch (status) {
    null => RetellKeyPointVisual(
      color: theme.colorScheme.outline,
      icon: Icons.more_horiz_rounded,
      label: l10n.retellAiReviewEvaluating,
    ),
    RetellReviewKeyPointStatus.covered => RetellKeyPointVisual(
      color: isDark ? _perfectDark : _perfectLight,
      icon: Icons.check_circle_rounded,
      label: l10n.retellAiReviewStatusCovered,
    ),
    RetellReviewKeyPointStatus.partial => RetellKeyPointVisual(
      color: isDark ? _fairDark : _fairLight,
      icon: Icons.contrast_rounded,
      label: l10n.retellAiReviewStatusPartial,
    ),
    RetellReviewKeyPointStatus.missed => RetellKeyPointVisual(
      color: theme.colorScheme.outline,
      icon: Icons.radio_button_unchecked_rounded,
      label: l10n.retellAiReviewStatusMissed,
    ),
    RetellReviewKeyPointStatus.distorted => RetellKeyPointVisual(
      color: isDark ? _poorDark : _poorLight,
      icon: Icons.swap_horiz_rounded,
      label: l10n.retellAiReviewStatusDistorted,
    ),
  };
}

/// 更正句使用的成功色（与 covered 同色系，表示「这样说更好」）。
Color retellCorrectionColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? _perfectDark
    : _perfectLight;

/// 单条纠错类别的视觉描述。
class RetellCorrectionTypeVisual {
  /// 类别标签与原句共用的颜色。
  final Color color;

  /// 类别标签文案；类别未到达时为空串，调用方据此不渲染标签。
  final String label;

  /// 原句是否画删除线。
  ///
  /// 只有 grammar / wordChoice 是「说错了」；redundancy / phrasing / cohesion
  /// 的原句本身不算错，划掉会误导用户，只用箭头 + 更正表达「可以更好」。
  final bool strikeThrough;

  const RetellCorrectionTypeVisual({
    required this.color,
    required this.label,
    required this.strikeThrough,
  });
}

/// 生成纠错类别的视觉描述。
///
/// [type] 为 null 表示该条纠错的类别尚未到达或无法识别，返回中性视觉且不带标签。
RetellCorrectionTypeVisual retellCorrectionTypeVisual(
  BuildContext context,
  AppLocalizations l10n,
  RetellReviewCorrectionType? type,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final errorColor = isDark ? _poorDark : _poorLight;
  final softColor = isDark ? _fairDark : _fairLight;
  return switch (type) {
    null => RetellCorrectionTypeVisual(
      color: theme.colorScheme.onSurfaceVariant,
      label: '',
      strikeThrough: false,
    ),
    RetellReviewCorrectionType.grammar => RetellCorrectionTypeVisual(
      color: errorColor,
      label: l10n.retellAiReviewCorrectionTypeGrammar,
      strikeThrough: true,
    ),
    RetellReviewCorrectionType.wordChoice => RetellCorrectionTypeVisual(
      color: errorColor,
      label: l10n.retellAiReviewCorrectionTypeWordChoice,
      strikeThrough: true,
    ),
    RetellReviewCorrectionType.redundancy => RetellCorrectionTypeVisual(
      color: softColor,
      label: l10n.retellAiReviewCorrectionTypeRedundancy,
      strikeThrough: false,
    ),
    RetellReviewCorrectionType.phrasing => RetellCorrectionTypeVisual(
      color: softColor,
      label: l10n.retellAiReviewCorrectionTypePhrasing,
      strikeThrough: false,
    ),
    RetellReviewCorrectionType.cohesion => RetellCorrectionTypeVisual(
      color: softColor,
      label: l10n.retellAiReviewCorrectionTypeCohesion,
      strikeThrough: false,
    ),
  };
}
