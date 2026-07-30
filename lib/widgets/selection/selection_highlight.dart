/// 选区高亮（L2）：按矩形绘制平台选中背景色
///
/// 画在文字**下面**（`CustomPaint.painter` 在 child 之前绘制），颜色取平台默认
/// 选中色（见 `platform_text_selection_style.dart` 建立的 [DefaultSelectionStyle]），
/// 矩形由 L3 后端按 `BoxHeightStyle.tight` 给出，贴合字形而不含行高 leading。
library;

import 'package:flutter/material.dart';

/// 选区高亮画笔。
class SelectionHighlightPainter extends CustomPainter {
  const SelectionHighlightPainter({required this.rects, required this.color});

  /// 高亮矩形（内容局部坐标）。
  final List<Rect> rects;

  /// 平台选中背景色。
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;
    final paint = Paint()..color = color;
    for (final rect in rects) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(SelectionHighlightPainter oldDelegate) =>
      oldDelegate.color != color || !_sameRects(oldDelegate.rects, rects);

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 取当前平台的选中背景色。
///
/// 优先用 [DefaultSelectionStyle]（`PlatformTextSelectionStyle` 已按平台设好），
/// 回退到主题主色的半透明，保证任何宿主下都有可见高亮。
Color resolveSelectionColor(BuildContext context) {
  final style = DefaultSelectionStyle.of(context).selectionColor;
  if (style != null) return style;
  return Theme.of(context).colorScheme.primary.withValues(alpha: 0.4);
}
