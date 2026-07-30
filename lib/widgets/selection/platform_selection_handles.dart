/// 选区手柄（L2）：平台默认画笔 + 按下即抢占的拖拽
///
/// 手柄**视觉完全由平台提供**——`TextSelectionControls.buildHandle` 就是
/// `SelectableText` / `TextField` 在用的那支画笔（iOS 竖线+圆点、Android 水滴、
/// 桌面无手柄），锚点与尺寸也取自 `getHandleAnchor` / `getHandleSize`，不自绘、
/// 不复刻。平台选择与 `SelectableText` 的 switch 保持一致。
///
/// **刻意不用 `SelectionOverlay`**：它把手柄挂到「最近包含 context 的 Overlay」，
/// 手柄会跑到根 Overlay 去，于是页面内的词典面板遮挡、随正文滚动都得手算几何
/// （这正是 2026-07-29 那批补丁的来源）。这里把手柄当普通 widget 放进正文所在的
/// Stack：滚动跟随、滚出剪裁、被面板遮挡全部是布局的自然结果。
///
/// 拖拽用 [ImmediateMultiDragGestureRecognizer]（系统选择手柄同款思路）：按下即
/// 赢得手势竞技场，压制外层滚动 / PageView 横滑 / 长按，因此宿主的「长按复制
/// 整句」可以原样保留。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 取当前平台的手柄画笔（与 `SelectableText` 的平台 switch 一致）。
TextSelectionControls platformHandleControls(BuildContext context) {
  return switch (Theme.of(context).platform) {
    TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
    TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
    TargetPlatform.android ||
    TargetPlatform.fuchsia => materialTextSelectionHandleControls,
    TargetPlatform.linux ||
    TargetPlatform.windows => desktopTextSelectionHandleControls,
  };
}

/// 手柄命中区最小边长（dp）。平台画笔本身可能只有 8~12dp 宽，直接拿它当命中区
/// 太难抓；这里以平台锚点为中心放大到可点尺寸，视觉位置不变。
const double kSelectionHandleHitSize = 36;

/// 计算手柄命中区（内容局部坐标）。
///
/// 与 [SelectionHandle] 的定位公式共用，保证「能拖到的位置」与「屏障放行的
/// 位置」永远一致——历史上这两处不一致导致句子紧邻的下层控件被误放行。
Rect selectionHandleHitRect({
  required TextSelectionControls controls,
  required Rect anchor,
  required bool isStart,
}) {
  final center = _handleVisualCenter(
    controls: controls,
    anchor: anchor,
    isStart: isStart,
  );
  return Rect.fromCenter(
    center: center,
    width: kSelectionHandleHitSize,
    height: kSelectionHandleHitSize,
  );
}

/// 手柄视觉中心（内容局部坐标）：由平台的 anchor/size 推导，不手写公式。
Offset _handleVisualCenter({
  required TextSelectionControls controls,
  required Rect anchor,
  required bool isStart,
}) {
  final lineHeight = anchor.height;
  final size = controls.getHandleSize(lineHeight);
  final handleAnchor = controls.getHandleAnchor(
    isStart ? TextSelectionHandleType.left : TextSelectionHandleType.right,
    lineHeight,
  );
  // 平台约定：把手柄自身的 handleAnchor 点对齐到选区端点（起始=左上，结束=右下）。
  final endpoint = isStart
      ? Offset(anchor.left, anchor.top)
      : Offset(anchor.right, anchor.top);
  final topLeft = endpoint - handleAnchor;
  return topLeft + Offset(size.width / 2, size.height / 2);
}

/// 单个选区手柄（平台画笔 + 拖拽）。
class SelectionHandle extends StatelessWidget {
  const SelectionHandle({
    super.key,
    required this.controls,
    required this.anchor,
    required this.isStart,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  /// 平台手柄画笔。
  final TextSelectionControls controls;

  /// 选区端点锚点矩形（内容局部坐标，高度为行高）。
  final Rect anchor;

  /// 是否为起始手柄。
  final bool isStart;

  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    final lineHeight = anchor.height;
    final size = controls.getHandleSize(lineHeight);
    if (size.isEmpty) return const SizedBox.shrink();
    final hitRect = selectionHandleHitRect(
      controls: controls,
      anchor: anchor,
      isStart: isStart,
    );
    final center = _handleVisualCenter(
      controls: controls,
      anchor: anchor,
      isStart: isStart,
    );
    return Positioned(
      left: hitRect.left,
      top: hitRect.top,
      width: hitRect.width,
      height: hitRect.height,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          ImmediateMultiDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                ImmediateMultiDragGestureRecognizer
              >(ImmediateMultiDragGestureRecognizer.new, (recognizer) {
                recognizer.onStart = (offset) => _HandleDrag(
                  onStart: () => onDragStart(offset),
                  onUpdate: (details) => onDragUpdate(details.globalPosition),
                  onEnd: onDragEnd,
                  onCancel: onDragCancel,
                );
              }),
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: center.dx - hitRect.left - size.width / 2,
              top: center.dy - hitRect.top - size.height / 2,
              width: size.width,
              height: size.height,
              // 平台画笔自带形状与配色（配色取自 TextSelectionTheme /
              // CupertinoTheme 的 selectionHandleColor）。
              child: controls.buildHandle(
                context,
                isStart
                    ? TextSelectionHandleType.left
                    : TextSelectionHandleType.right,
                lineHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 手柄拖拽会话（[ImmediateMultiDragGestureRecognizer] 的 [Drag] 载体）。
class _HandleDrag extends Drag {
  _HandleDrag({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  }) {
    onStart();
  }

  final VoidCallback onStart;
  final void Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  void update(DragUpdateDetails details) => onUpdate(details);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onCancel();
}
