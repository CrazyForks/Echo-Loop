/// 带锚点的共享文字操作栏。
///
/// 统一提供横向布局、边界避让、溢出分页和桌面悬浮反馈；按钮宽度按各自文案
/// 独立计算（不统一取最长文案等宽），避免某个按钮文案变化时牵动其余按钮宽度
/// 一起变化。
library;

import 'package:flutter/cupertino.dart';

/// 共享操作栏动作。
class AnchoredActionBarAction {
  const AnchoredActionBarAction({required this.label, required this.onPressed});

  /// 已本地化的按钮文案。
  final String label;

  /// 点击回调。
  final VoidCallback onPressed;
}

/// 围绕指定锚点显示的共享文字操作栏。
class AnchoredActionBar extends StatelessWidget {
  const AnchoredActionBar({
    super.key,
    required this.anchors,
    required this.actions,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<AnchoredActionBarAction> actions;

  static const double _buttonHorizontalPadding = 16;
  static const double _buttonVerticalPadding = 4;
  static const double _buttonFontSize = 15;
  static const double _buttonMinWidth = 72;
  static const BorderRadius _toolbarBorderRadius = BorderRadius.all(
    Radius.circular(10),
  );

  @override
  Widget build(BuildContext context) {
    return CupertinoTextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: _buildPlainToolbar,
      children: [
        for (final action in actions)
          _AnchoredActionBarButton(
            key: ValueKey('selection_toolbar_button_${action.label}'),
            text: action.label,
            width: _buttonWidth(context, action.label),
            onPressed: action.onPressed,
          ),
      ],
    );
  }

  /// 按自身文案计算按钮宽度，保证单个按钮文案变化不影响其余按钮。
  static double _buttonWidth(BuildContext context, String label) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: _buttonFontSize),
      ),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final contentWidth = painter.width + _buttonHorizontalPadding * 2;
    return contentWidth < _buttonMinWidth ? _buttonMinWidth : contentWidth;
  }

  /// 无箭头工具条外壳；定位和分页仍交给 Flutter 官方组件处理。
  static Widget _buildPlainToolbar(
    BuildContext context,
    Offset anchorAbove,
    Offset anchorBelow,
    Widget child,
  ) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return DecoratedBox(
      key: const ValueKey('selection_toolbar_surface'),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222222) : const Color(0xFFF6F6F6),
        borderRadius: _toolbarBorderRadius,
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(borderRadius: _toolbarBorderRadius, child: child),
    );
  }
}

/// 共享操作栏按钮：提供桌面悬浮、按压和点击光标反馈。
class _AnchoredActionBarButton extends StatefulWidget {
  const _AnchoredActionBarButton({
    super.key,
    required this.text,
    required this.width,
    required this.onPressed,
  });

  final String text;
  final double width;
  final VoidCallback onPressed;

  @override
  State<_AnchoredActionBarButton> createState() =>
      _AnchoredActionBarButtonState();
}

class _AnchoredActionBarButtonState extends State<_AnchoredActionBarButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final tint = isDark ? CupertinoColors.white : CupertinoColors.black;
    final overlayAlpha = _pressed ? 0.16 : (_hovered ? 0.08 : 0.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: Container(
          width: widget.width,
          alignment: Alignment.center,
          color: tint.withValues(alpha: overlayAlpha),
          padding: const EdgeInsets.symmetric(
            horizontal: AnchoredActionBar._buttonHorizontalPadding,
            vertical: AnchoredActionBar._buttonVerticalPadding,
          ),
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: AnchoredActionBar._buttonFontSize,
              fontWeight: FontWeight.normal,
              color: tint,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
