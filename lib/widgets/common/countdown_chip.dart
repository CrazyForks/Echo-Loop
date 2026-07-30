/// 倒计时控制按钮（共享组件）
///
/// 56×56 圆形按钮，外围带进度环，内部显示倒计时秒数，
/// 默认右下角显示暂停/恢复小徽章。调用方可提供 [onTap]，将点击改为
/// 接管自动流程（例如进入等待用户操作）。
///
/// **自驱动动画**：内部使用 [AnimationController] 驱动进度环和秒数，
/// 不依赖外部高频传入 remaining，避免 Provider 每 100ms rebuild。
///
/// **快进内置**：收到 [isFastForward] = true 时，自动将剩余动画压缩到
/// ~1 秒内完成，调用方无需关心具体速度。
///
/// **纯展示组件**：只负责倒计时圆环，快进按钮由调用方控制。
library;

import 'package:flutter/material.dart';
import 'tappable_wrapper.dart';

/// 倒计时控制按钮
///
/// 接收 [total]（总时长）、[isPaused]、[isFastForward]，内部自行驱动动画。
/// 点击自动切换暂停/恢复。
class CountdownChip extends StatefulWidget {
  /// 倒计时总时长
  final Duration total;

  /// 是否已暂停
  final bool isPaused;

  /// 是否快进中（剩余动画将在 ~1 秒内完成）
  final bool isFastForward;

  /// 暂停回调
  final VoidCallback onPause;

  /// 恢复回调
  final VoidCallback onResume;

  /// 自定义点击动作。提供后优先于暂停/恢复。
  final VoidCallback? onTap;

  const CountdownChip({
    super.key,
    required this.total,
    required this.isPaused,
    this.isFastForward = false,
    required this.onPause,
    required this.onResume,
    this.onTap,
  });

  @override
  State<CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<CountdownChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// 快进目标时长
  static const _fastForwardDuration = Duration(milliseconds: 1000);

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    if (!widget.isPaused) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant CountdownChip oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 总时长变化 → 新的倒计时，重建 controller
    if (widget.total != oldWidget.total) {
      final wasAnimating = _controller.isAnimating;
      _controller.dispose();
      _controller = _createController();
      if (wasAnimating && !widget.isPaused) _controller.forward();
      return;
    }

    // 快进状态变化
    if (widget.isFastForward != oldWidget.isFastForward) {
      _applyFastForward();
      return;
    }

    // 暂停/恢复
    if (widget.isPaused && !oldWidget.isPaused) {
      _controller.stop();
    } else if (!widget.isPaused && oldWidget.isPaused) {
      _controller.forward();
    }
  }

  /// 创建 AnimationController，正常速度 = total 时长
  AnimationController _createController() {
    return AnimationController(vsync: this, duration: widget.total)
      ..addListener(_onTick);
  }

  /// 快进/恢复正常速度
  void _applyFastForward() {
    final currentValue = _controller.value;
    _controller.stop();

    if (widget.isFastForward) {
      // 快进：让剩余动画在 ~1 秒内走完
      final remainingFraction = 1.0 - currentValue;
      if (remainingFraction > 0) {
        // duration 是 0→1 的总时长，只跑 remainingFraction 这段
        // 实际耗时 = duration × remainingFraction = 1500ms
        final fullDurationMs =
            _fastForwardDuration.inMilliseconds / remainingFraction;
        _controller.duration = Duration(milliseconds: fullDurationMs.round());
      }
    } else {
      // 恢复正常速度
      _controller.duration = widget.total;
    }

    if (!widget.isPaused) {
      _controller.forward(from: currentValue);
    }
  }

  void _onTick() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _controller.value; // 0.0 → 1.0（已过时间占比）
    final totalMs = widget.total.inMilliseconds;
    final remainingMs = ((1.0 - progress) * totalMs).round();
    final seconds = (remainingMs / 1000).ceil();

    return TappableWrapper(
      onTap:
          widget.onTap ?? (widget.isPaused ? widget.onResume : widget.onPause),
      feedbackType: TapFeedback.scale,
      scaleDown: 0.90,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                valueColor: AlwaysStoppedAnimation(
                  theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
              ),
            ),
            Text(
              '$seconds',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            // 自定义动作用停止脚标提示“点击后停止自动推进”。
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer,
                  border: Border.all(color: theme.colorScheme.surface),
                ),
                child: Icon(
                  widget.onTap != null
                      ? Icons.stop_rounded
                      : (widget.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded),
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
