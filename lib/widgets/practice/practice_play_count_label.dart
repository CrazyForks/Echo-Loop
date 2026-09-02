/// 练习页面共享的遍数 + 模式标签
///
/// 自动模式：显示 "自动 · 第 1/3 遍"，弱化样式。
/// 手动模式：显示 "手动"，沿用自动模式的弱化样式。
/// 可选 [statusSuffixText] 用于追加当前会话参数，例如播放速度。
/// 用于所有学习页面（精听、跟读、难句补练、收藏复习、复述、盲听）。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 格式化练习页的遍数文案。
///
/// [totalCount] 为 `0` 时表示无限重复，统一显示为 `∞`。
String formatPracticePlayCount(
  AppLocalizations l10n, {
  required int currentCount,
  required int totalCount,
}) {
  final totalLabel = totalCount == 0 ? '∞' : '$totalCount';
  final languageCode = l10n.localeName.toLowerCase();
  if (languageCode.startsWith('zh')) {
    return '第 $currentCount/$totalLabel 遍';
  }
  return 'Round $currentCount/$totalLabel';
}

/// 遍数 + 模式标签
class PracticePlayCountLabel extends StatelessWidget {
  /// 是否为手动模式
  final bool isManualMode;

  /// 预格式化的遍数文本（如 "第 1/3 遍" / "第 2/∞ 遍"）
  final String playCountText;

  /// 可选状态后缀（如 "1.3x"），由具体练习页面决定是否展示。
  final String? statusSuffixText;

  /// 本地化
  final AppLocalizations l10n;

  /// 主题
  final ThemeData theme;

  const PracticePlayCountLabel({
    super.key,
    required this.isManualMode,
    required this.playCountText,
    this.statusSuffixText,
    required this.l10n,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return isManualMode ? _buildManualLabel() : _buildAutoLabel();
  }

  /// 手动模式：显示 "手动"，与自动模式保持相同的弱化样式。
  Widget _buildManualLabel() {
    final suffix = statusSuffixText;
    return Text(
      suffix == null
          ? l10n.practiceControlModeManual
          : '${l10n.practiceControlModeManual} · $suffix',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  /// 自动模式：弱化 "自动 · 第 1/3 遍"
  Widget _buildAutoLabel() {
    final suffix = statusSuffixText;
    return Text(
      suffix == null
          ? '${l10n.practiceControlModeAuto} · $playCountText'
          : '${l10n.practiceControlModeAuto} · $playCountText · $suffix',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
