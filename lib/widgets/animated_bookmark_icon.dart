import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 带缩放弹跳动画的书签图标按钮
///
/// 收藏/取消收藏时播放缩放动画（0.7 → 1.2 → 1.0），
/// 让状态切换更醒目。
class AnimatedBookmarkIcon extends StatefulWidget {
  /// 是否已收藏
  final bool isSaved;

  /// 图标大小
  final double size;

  /// 收藏状态颜色
  final Color? savedColor;

  /// 未收藏状态颜色
  final Color? unsavedColor;

  /// 点击回调
  final VoidCallback? onPressed;

  const AnimatedBookmarkIcon({
    super.key,
    required this.isSaved,
    this.size = 24,
    this.savedColor,
    this.unsavedColor,
    this.onPressed,
  });

  @override
  State<AnimatedBookmarkIcon> createState() => _AnimatedBookmarkIconState();
}

class _AnimatedBookmarkIconState extends State<AnimatedBookmarkIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  /// 记录上一次的收藏状态，用于检测变化
  late bool _previousSaved;

  @override
  void initState() {
    super.initState();
    _previousSaved = widget.isSaved;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // 缩放序列：先缩小到 0.7，再弹到 1.2，最后回到 1.0
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.7), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(AnimatedBookmarkIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 收藏状态变化时播放动画
    if (widget.isSaved != _previousSaved) {
      _previousSaved = widget.isSaved;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedColor = widget.savedColor ?? AppTheme.bookmarkColor;
    final unsavedColor =
        widget.unsavedColor ?? theme.colorScheme.onSurfaceVariant;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: widget.onPressed,
        icon: Icon(
          widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
          size: widget.size,
          color: widget.isSaved ? savedColor : unsavedColor,
        ),
      ),
    );
  }
}
