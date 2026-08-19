/// 简报弹窗底部操作按钮行（通用）
///
/// 统一各任务简报弹窗的「开始练习」+ 可选「跳过」按钮布局，
/// 与复述简报（[showParagraphSelectionSheet]）的跳过按钮视觉保持一致：
/// 无跳过回调时只显示整宽开始按钮；有跳过回调时显示
/// 「跳过(flex1 灰底 tonal) + 开始(flex2)」并排。
library;

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 简报弹窗底部按钮行
class BriefingActionRow extends StatelessWidget {
  /// 开始按钮文案
  final String startLabel;

  /// 开始按钮图标（默认播放图标）
  final IconData startIcon;

  /// 点击开始的回调（导航/弹窗关闭由调用方在回调内处理）
  final VoidCallback onStart;

  /// 是否允许开始当前练习，用于入口内容为空时保留原因文案但禁止操作。
  final bool isStartEnabled;

  /// 跳过按钮文案，与 [onSkip] 同时提供时才显示跳过按钮
  final String? skipLabel;

  /// 点击跳过的回调（导航/弹窗关闭由调用方在回调内处理）
  final VoidCallback? onSkip;

  const BriefingActionRow({
    super.key,
    required this.startLabel,
    required this.onStart,
    this.isStartEnabled = true,
    this.startIcon = Icons.play_arrow,
    this.skipLabel,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final startButton = FilledButton.icon(
      onPressed: isStartEnabled ? onStart : null,
      icon: Icon(startIcon),
      label: Text(startLabel),
    );

    final label = skipLabel;
    final skip = onSkip;
    if (label == null || skip == null) {
      return SizedBox(width: double.infinity, child: startButton);
    }

    final skipButton = FilledButton.tonal(
      onPressed: skip,
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        // 纯黑深色主题下底色与背景接近，加描边保证按钮边界清晰
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    return Row(
      children: [
        Expanded(flex: 1, child: skipButton),
        const SizedBox(width: AppSpacing.m),
        Expanded(flex: 2, child: startButton),
      ],
    );
  }
}
