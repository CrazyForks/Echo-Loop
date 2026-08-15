/// 播放控制栏（所有学习页面共享）
///
/// 通用的 [上一个] [播放/暂停] [下一个/完成] 控制栏。
/// 回调驱动，不依赖任何具体 Provider。
/// 用于盲听、精听、跟读、复述、难句补练、收藏复习页面。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../guide_flow.dart';

/// 播放控制栏：[上一个] [播放/暂停] [下一个/完成]
class PlaybackControls extends StatelessWidget {
  static const double controlButtonSize = 56;
  static const double controlButtonGap = 24;

  /// 是否可以返回上一个
  final bool canGoPrev;

  /// 是否为最后一个（影响下一个按钮图标：skip_next → check_circle）
  final bool isLast;

  /// 中间按钮图标（播放/暂停）
  final IconData centerIcon;

  /// 中间按钮点击回调
  final VoidCallback? onCenter;

  /// 上一个回调
  final VoidCallback? onPrevious;

  /// 下一个回调
  final VoidCallback? onNext;

  /// 可选的右侧自定义控件；未提供时显示下一句/完成图标。
  final Widget? nextControl;

  /// 自定义右侧控件占用的布局宽度，控件自身尺寸由调用方管理。
  final double? nextControlWidth;

  /// 可选：中间按钮的新手引导步骤，提供时会用 [GuideTarget] 包裹中间按钮
  final GuideStep? centerGuideStep;

  const PlaybackControls({
    super.key,
    required this.canGoPrev,
    required this.isLast,
    required this.centerIcon,
    this.onCenter,
    this.onPrevious,
    this.onNext,
    this.nextControl,
    this.nextControlWidth,
    this.centerGuideStep,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final centerButton = SizedBox.square(
      dimension: controlButtonSize,
      child: IconButton.filled(
        onPressed: onCenter,
        icon: Icon(centerIcon),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(controlButtonSize),
          iconSize: 28,
          foregroundColor: theme.colorScheme.onPrimary,
          backgroundColor: theme.colorScheme.primary,
          disabledForegroundColor: theme.colorScheme.onPrimary.withValues(
            alpha: 0.38,
          ),
          disabledBackgroundColor: theme.colorScheme.primary.withValues(
            alpha: 0.38,
          ),
          hoverColor: theme.colorScheme.onPrimary.withValues(alpha: 0.08),
          focusColor: theme.colorScheme.onPrimary.withValues(alpha: 0.12),
          highlightColor: theme.colorScheme.onPrimary.withValues(alpha: 0.12),
          elevation: 2,
          shadowColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
    );

    final centerStep = centerGuideStep;
    final centerWidget = centerStep != null
        ? GuideTarget(step: centerStep, child: centerButton)
        : centerButton;

    final previousWidget = PlaybackNavButton(
      icon: Icons.skip_previous_rounded,
      enabled: canGoPrev,
      onTap: canGoPrev ? onPrevious : null,
    );
    final nextRegionChild =
        nextControl ??
        PlaybackNavButton(
          icon: isLast ? Icons.check_circle_rounded : Icons.skip_next_rounded,
          enabled: true,
          onTap: onNext,
        );

    // 播放按钮必须始终固定在正中间，不能随 nextControl 的宽度变化而挪动。
    // 用左右两个等 flex 的 Expanded 包住上一句/下一句区域：无论 nextControl
    // 多宽，两侧分配到的空间永远相等，播放按钮的位置只取决于这个等分点，
    // 和 nextControl 本身的宽度完全无关。
    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredWidth =
            controlButtonSize * 2 +
            controlButtonGap * 2 +
            (nextControl != null
                ? (nextControlWidth ?? controlButtonSize)
                : controlButtonSize);
        final horizontalPadding = math
            .max(
              0,
              math.min(
                AppSpacing.l,
                (constraints.maxWidth - requiredWidth) / 2,
              ),
            )
            .toDouble();
        final controls = Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: previousWidget,
              ),
            ),
            const SizedBox(width: controlButtonGap),
            centerWidget,
            const SizedBox(width: controlButtonGap),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: nextRegionChild,
              ),
            ),
          ],
        );
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: controls,
        );
      },
    );
  }
}

/// 导航按钮（上一个/下一个/完成）
class PlaybackNavButton extends StatelessWidget {
  /// 按钮图标
  final IconData icon;

  /// 是否可用
  final bool enabled;

  /// 点击回调
  final VoidCallback? onTap;

  const PlaybackNavButton({
    super.key,
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconWidget = enabled
        ? Opacity(
            opacity: 0.6,
            child: Icon(icon, size: 32, color: colorScheme.onSurface),
          )
        : AnimatedOpacity(
            opacity: 0.15,
            duration: const Duration(milliseconds: 150),
            child: Icon(icon, size: 32, color: colorScheme.onSurface),
          );

    return SizedBox.square(
      dimension: PlaybackControls.controlButtonSize,
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: iconWidget,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(PlaybackControls.controlButtonSize),
          hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
          focusColor: colorScheme.onSurface.withValues(alpha: 0.12),
          highlightColor: colorScheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: colorScheme.onSurface,
        ),
      ),
    );
  }
}
