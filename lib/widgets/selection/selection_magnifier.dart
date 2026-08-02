/// 拖选放大镜（L2）
///
/// 复用 Flutter 内置的 [TextMagnifier]：移动端按平台渲染 iOS/Android 各自的样式，
/// 桌面端 `magnifierBuilder` 返回 null 而自动不显示。坐标按 [MagnifierInfo] 的
/// 约定换算到 root overlay。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'selection_backend.dart';

const double _kVisualMagnifierVerticalOffset = -10;

/// Android 放大镜的 Material 位置与轮廓绘制。
///
/// Flutter 默认 [TextMagnifier] 的 Android 阴影很淡，复杂背景下不容易看出镜框；
/// 这里保留相同的定位规则，只增强常见的细边框和外阴影。
class _AndroidSelectionMagnifier extends StatefulWidget {
  const _AndroidSelectionMagnifier({required this.magnifierInfo});

  final ValueNotifier<MagnifierInfo> magnifierInfo;

  @override
  State<_AndroidSelectionMagnifier> createState() =>
      _AndroidSelectionMagnifierState();
}

class _AndroidSelectionMagnifierState
    extends State<_AndroidSelectionMagnifier> {
  Offset? _position;
  Offset _focalPointAdjustment = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.magnifierInfo.addListener(_updatePosition);
  }

  @override
  void didChangeDependencies() {
    _updatePosition();
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    widget.magnifierInfo.removeListener(_updatePosition);
    super.dispose();
  }

  void _updatePosition() {
    final info = widget.magnifierInfo.value;
    final screenRect = Offset.zero & MediaQuery.sizeOf(context);
    const size = Magnifier.kDefaultMagnifierSize;
    const verticalFocalPointShift = Magnifier.kStandardVerticalFocalPointShift;
    final magnifierX = info.globalGesturePosition.dx
        .clamp(
          info.currentLineBoundaries.left,
          info.currentLineBoundaries.right,
        )
        .toDouble();
    final unadjustedRect =
        Offset(
              magnifierX,
              info.caretRect.center.dy + _kVisualMagnifierVerticalOffset,
            ) -
            Offset(size.width / 2, size.height + verticalFocalPointShift) &
        size;
    final position = MagnifierController.shiftWithinBounds(
      bounds: screenRect,
      rect: unadjustedRect,
    );
    const magnificationScale = 1.25;
    final horizontalMaxFocalPointEdgeInsets =
        (size.width / 2) / magnificationScale;
    final focalPointX =
        info.fieldBounds.width < horizontalMaxFocalPointEdgeInsets * 2
        ? info.fieldBounds.center.dx
        : info.globalGesturePosition.dx.clamp(
            info.fieldBounds.left + horizontalMaxFocalPointEdgeInsets,
            info.fieldBounds.right - horizontalMaxFocalPointEdgeInsets,
          );
    final focalPointAdjustment = Offset(
      focalPointX - position.center.dx,
      unadjustedRect.top - position.top - _kVisualMagnifierVerticalOffset,
    );
    if (!mounted) {
      _position = position.topLeft;
      _focalPointAdjustment = focalPointAdjustment;
      return;
    }
    setState(() {
      _position = position.topLeft;
      _focalPointAdjustment = focalPointAdjustment;
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    if (position == null) return const SizedBox.shrink();
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: RawMagnifier(
        size: Magnifier.kDefaultMagnifierSize,
        magnificationScale: 1.25,
        focalPointOffset:
            _focalPointAdjustment +
            Offset(
              0,
              Magnifier.kStandardVerticalFocalPointShift +
                  Magnifier.kDefaultMagnifierSize.height / 2,
            ),
        decoration: const MagnifierDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(40)),
            side: BorderSide(color: Color.fromARGB(70, 0, 0, 0), width: 0.75),
          ),
          shadows: <BoxShadow>[
            BoxShadow(
              color: Color.fromARGB(35, 0, 0, 0),
              blurRadius: 3,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: const ColoredBox(color: Color.fromARGB(8, 158, 158, 158)),
      ),
    );
  }
}

/// 拖选期间的放大镜。
///
/// 谁创建谁销毁：拥有它的组件在 dispose 里调 [dispose]。
class SelectionMagnifier {
  /// 在平台默认位置基础上把放大镜再向上移一点，避免镜框贴近手指和手柄。
  ///
  /// 这不改变选区和手柄的几何，平台放大、边界处理和 iOS 隐藏阈值仍按 Flutter
  /// 默认规则执行；平台放大镜相对自身焦点的间距也保持不变。
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
    // Android 位置器会单独把镜框上移，caretRect 保持在原文字位置，避免放大内容
    // 跟着镜框一起偏移；iOS 继续使用 Flutter 自带的位置器。
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
    final magnifier = switch (defaultTargetPlatform) {
      TargetPlatform.android => _AndroidSelectionMagnifier(
        magnifierInfo: _info,
      ),
      _ => TextMagnifier.adaptiveMagnifierConfiguration.magnifierBuilder(
        context,
        _controller,
        _info,
      ),
    };
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
