/// 选区几何小工具（L2）
library;

import 'package:flutter/rendering.dart';

/// 矩形列表的并集；空列表返回 null。
Rect? unionOfRects(List<Rect> rects) {
  if (rects.isEmpty) return null;
  var union = rects.first;
  for (final rect in rects.skip(1)) {
    union = union.expandToInclude(rect);
  }
  return union;
}

/// [rects]（[content] 局部坐标）是否还与最近的可滚动视口相交。
///
/// 选区操作条挂在页面级宿主上（不在 Scrollable 内），所以正文被滚出视口时必须
/// 主动收起操作条，否则气泡会孤零零浮在无关内容上。内容不在 Scrollable 内时
/// 恒返回 true。
bool rectsVisibleInViewport(RenderBox content, List<Rect> rects) {
  final union = unionOfRects(rects);
  if (union == null) return false;
  final viewport = RenderAbstractViewport.maybeOf(content);
  if (viewport is! RenderBox) return true;
  final viewportBox = viewport as RenderBox;
  if (!viewportBox.hasSize || !content.attached) return true;
  final inViewport = MatrixUtils.transformRect(
    content.getTransformTo(viewportBox),
    union,
  );
  return (Offset.zero & viewportBox.size).overlaps(inViewport);
}
