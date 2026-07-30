/// 拖选放大镜（L2）
///
/// 复用 Flutter 内置的 [TextMagnifier]：移动端按平台渲染 iOS/Android 各自的样式，
/// 桌面端 `magnifierBuilder` 返回 null 而自动不显示。坐标按 [MagnifierInfo] 的
/// 约定换算到 root overlay。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'selection_backend.dart';

/// 拖选期间的放大镜。
///
/// 谁创建谁销毁：拥有它的组件在 dispose 里调 [dispose]。
class SelectionMagnifier {
  /// 按当前选区显示/更新放大镜（跟手的那一端由 [isStart] 指定）。
  ///
  /// 锚点直接问后端现算，**不用** post-frame 的几何缓存——缓存会慢一帧，放大镜
  /// 就跟不上手指。
  void showForSelection({
    required BuildContext context,
    required Widget debugRequiredFor,
    required SelectionBackend backend,
    required TextRange range,
    required Offset globalGesturePosition,
    required bool isStart,
  }) {
    final box = backend.contentBox;
    final anchors = backend.handleAnchors(range);
    if (box == null || anchors == null) return;
    final (startAnchor, endAnchor) = anchors;
    final anchor = isStart ? startAnchor : endAnchor;
    final caretX = isStart ? anchor.left : anchor.right;
    showOrUpdate(
      context: context,
      debugRequiredFor: debugRequiredFor,
      globalGesturePosition: globalGesturePosition,
      caretRect: Rect.fromLTWH(caretX, anchor.top, 0, anchor.height),
      contentBounds: Offset.zero & box.size,
      localToGlobal: box.localToGlobal,
    );
  }

  final MagnifierController _controller = MagnifierController();
  final ValueNotifier<MagnifierInfo> _info = ValueNotifier<MagnifierInfo>(
    MagnifierInfo.empty,
  );

  /// 显示或更新放大镜。
  ///
  /// [caretRect] 为选区端点在**内容局部坐标**下的竖线矩形（宽 0、高行高），
  /// [contentBounds] 为内容的局部绘制边界，[localToGlobal] 用于换算到 overlay。
  void showOrUpdate({
    required BuildContext context,
    required Widget debugRequiredFor,
    required Offset globalGesturePosition,
    required Rect caretRect,
    required Rect contentBounds,
    required Offset Function(Offset local) localToGlobal,
  }) {
    final overlayObject = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    if (overlayObject is! RenderBox) return;
    // 内容局部坐标 → overlay 局部坐标：两者原点之差即平移量。
    final shift =
        localToGlobal(Offset.zero) - overlayObject.localToGlobal(Offset.zero);
    final caretInOverlay = caretRect.shift(shift);
    final boundsInOverlay = contentBounds.shift(shift);
    _info.value = MagnifierInfo(
      // 触点 Y 用 caret 中心：结束手柄位于文字下方时，用手指原始 Y 会被 iOS 的
      // 阈值判断为「应隐藏」。
      globalGesturePosition: Offset(
        overlayObject.globalToLocal(globalGesturePosition).dx,
        caretInOverlay.center.dy,
      ),
      caretRect: caretInOverlay,
      fieldBounds: boundsInOverlay,
      currentLineBoundaries: Rect.fromLTRB(
        boundsInOverlay.left,
        caretInOverlay.top,
        boundsInOverlay.right,
        caretInOverlay.bottom,
      ),
    );
    if (_controller.overlayEntry != null) return;
    final magnifier = TextMagnifier.adaptiveMagnifierConfiguration
        .magnifierBuilder(context, _controller, _info);
    if (magnifier == null) return;
    _controller.show(
      context: context,
      debugRequiredFor: debugRequiredFor,
      builder: (_) => magnifier,
    );
  }

  /// 隐藏放大镜（松手、取消、会话结束）。
  void hide() => unawaited(_controller.hide());

  /// [MagnifierController] 本身没有 dispose：`hide()` 会移除 overlay entry。
  void dispose() {
    hide();
    _info.dispose();
  }
}
