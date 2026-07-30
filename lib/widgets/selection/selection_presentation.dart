/// 选区呈现几何（L2）：高亮矩形、手柄锚点与操作条请求的缓存
///
/// 从交互内核里分出来的原因：几何是**派生状态**（由 L1 的字符区间 + 当前布局
/// 现算），它没有自己的语义，只需要在布局变化后重算并回答三个问题——
/// 「画在哪」「手柄在哪」「操作条锚点在哪」。把 diff 与换算收在这里，内核只保留
/// 会话与手势。
///
/// 所有矩形都是 `backend.contentBox` 的局部坐标。
library;

import 'package:flutter/material.dart';

import 'platform_selection_handles.dart';
import 'selection_backend.dart';
import 'selection_geometry.dart';
import 'selection_toolbar.dart';
import 'selection_toolbar_layer.dart';

/// 选区呈现几何缓存。
class SelectionPresentation {
  SelectionPresentation(this._backend);

  final SelectionBackend _backend;

  /// 高亮矩形（贴字形）。
  List<Rect> get highlightRects => _highlightRects;
  List<Rect> _highlightRects = const [];

  /// 起始/结束端锚点矩形（高度为行高，供平台手柄定位）。
  Rect? get startAnchor => _startAnchor;
  Rect? _startAnchor;

  Rect? get endAnchor => _endAnchor;
  Rect? _endAnchor;

  /// 内容左上角的全局坐标。
  ///
  /// 参与「几何是否变化」的判定：滚动时它会变，从而触发操作条锚点重算——这就是
  /// 操作条跟随内容滚动的机制（操作条挂在页面级宿主上，不在 Scrollable 内）。
  Offset? _contentGlobalOffset;

  /// 是否已有可用锚点（手柄可显示）。
  bool get hasAnchors => _startAnchor != null && _endAnchor != null;

  /// 清空缓存（会话结束、内容失效）。
  void reset() {
    _highlightRects = const [];
    _startAnchor = null;
    _endAnchor = null;
    _contentGlobalOffset = null;
  }

  /// 是否有值可清（避免无谓 setState）。
  bool get isEmpty => _highlightRects.isEmpty && _startAnchor == null;

  /// 按当前布局重算 [range] 的几何；返回是否发生变化。
  ///
  /// [range] 为空或后端未就绪时清空缓存。
  bool refresh(TextRange? range) {
    final box = _backend.contentBox;
    if (range == null || box == null) {
      if (isEmpty) return false;
      reset();
      return true;
    }
    final rects = _backend.highlightRects(range);
    final anchors = _backend.handleAnchors(range);
    if (anchors == null) return false;
    final (start, end) = anchors;
    final origin = box.localToGlobal(Offset.zero);
    final changed =
        !_sameRects(rects, _highlightRects) ||
        start != _startAnchor ||
        end != _endAnchor ||
        origin != _contentGlobalOffset;
    if (!changed) return false;
    _highlightRects = rects;
    _startAnchor = start;
    _endAnchor = end;
    _contentGlobalOffset = origin;
    return true;
  }

  /// 局部坐标是否命中任一手柄的命中区。
  ///
  /// 手柄会悬在文本 bounds 之外（首行上方 / 末行下方 / 行首左侧），「点面板外
  /// 关闭」屏障的豁免判定必须单独算它，且**不得整圈外扩**——历史上用「组件
  /// bounds 上下外扩 36dp」的粗矩形，句子紧邻的下层控件被误放行。
  bool hitsHandle(TextSelectionControls controls, Offset local) {
    final start = _startAnchor;
    final end = _endAnchor;
    if (start == null || end == null) return false;
    return selectionHandleHitRect(
          controls: controls,
          anchor: start,
          isStart: true,
        ).contains(local) ||
        selectionHandleHitRect(
          controls: controls,
          anchor: end,
          isStart: false,
        ).contains(local);
  }

  /// 选区是否还在最近的可滚动视口内（滚出视口即收起操作条）。
  bool get visibleInViewport {
    final box = _backend.contentBox;
    if (box == null) return false;
    return rectsVisibleInViewport(box, _highlightRects);
  }

  /// 组装操作条挂载请求（锚点为全局坐标）；几何不可用时返回 null。
  SelectionToolbarRequest? toolbarRequest({
    required Object owner,
    required List<SelectionToolbarAction> actions,
  }) {
    final box = _backend.contentBox;
    final start = _startAnchor;
    final end = _endAnchor;
    if (box == null || start == null || end == null || actions.isEmpty) {
      return null;
    }
    if (!visibleInViewport) return null;
    return SelectionToolbarRequest.forSelection(
      owner: owner,
      content: box,
      startAnchor: start,
      endAnchor: end,
      actions: actions,
    );
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
