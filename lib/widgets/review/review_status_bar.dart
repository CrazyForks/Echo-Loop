import 'dart:async';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 收藏复习页的低强调会话状态条，只在自身范围内刷新计时显示。
class ReviewStatusBar extends StatefulWidget {
  const ReviewStatusBar({
    required this.elapsed,
    required this.reviewedCount,
    required this.remainingCount,
    required this.elapsedLabel,
    required this.reviewedLabel,
    required this.remainingLabel,
    super.key,
  });

  final Duration Function() elapsed;
  final int reviewedCount;
  final int remainingCount;
  final String elapsedLabel;
  final String reviewedLabel;
  final String remainingLabel;

  @override
  State<ReviewStatusBar> createState() => _ReviewStatusBarState();
}

class _ReviewStatusBarState extends State<ReviewStatusBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasBottomSafeArea = MediaQuery.viewPaddingOf(context).bottom > 0;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.68),
      fontSize: 11,
    );
    final duration = widget.elapsed();
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    final time = hours > 0
        ? '$hours:${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
    final timeStyle = style?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // 复习状态条位于页面最底部，需要避让 Android 导航栏和 iOS Home Indicator，
    // 与学习任务底部控制区保持一致，避免被系统底部白色区域遮挡。
    return SafeArea(
      top: false,
      bottom: true,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.m,
          0,
          AppSpacing.m,
          hasBottomSafeArea ? 0 : 4,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          runSpacing: AppSpacing.xs,
          children: [
            Icon(Icons.timer_outlined, size: 13, color: style?.color),
            const SizedBox(width: AppSpacing.xs),
            Text(widget.elapsedLabel, style: style),
            const SizedBox(width: AppSpacing.xs),
            Text(time, style: timeStyle),
            const SizedBox(width: AppSpacing.l),
            Icon(Icons.check_circle_outline, size: 13, color: style?.color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${widget.reviewedLabel} ${widget.reviewedCount}',
              style: style,
            ),
            const SizedBox(width: AppSpacing.l),
            Icon(Icons.pending_actions_outlined, size: 13, color: style?.color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${widget.remainingLabel} ${widget.remainingCount}',
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}
