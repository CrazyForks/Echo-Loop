/// 选区手势接线（L2）：平台手势 → 回调
///
/// 只负责「哪种输入触发哪个回调」，不含任何选区状态，因此内核
/// （`selectable_content.dart`）里只剩语义。三条输入通道：
/// - **触屏**：tap（点词 / 取消）与长按拖选，用普通 [GestureDetector]；
/// - **鼠标**：按住拖动选择（桌面标准），用限定 [PointerDeviceKind.mouse] 的
///   [PanGestureRecognizer]，因此不与长按/滚动抢竞技场；
/// - **键盘**：[Focus] 只做键盘事件路由，**失焦不影响选区**（这正是自有选区存在
///   的理由，见 CLAUDE.md §7.28）；不参与 Tab 遍历（文本不是控件）。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 选区手势接线。
class SelectionGestureDetector extends StatelessWidget {
  const SelectionGestureDetector({
    super.key,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onTapUp,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onMouseDragStart,
    required this.onMouseDragUpdate,
    required this.onMouseDragEnd,
    required this.onMouseDragCancel,
    required this.child,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onKeyEvent;

  final GestureTapUpCallback onTapUp;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMoveUpdate;
  final GestureLongPressEndCallback onLongPressEnd;

  final GestureDragStartCallback onMouseDragStart;
  final GestureDragUpdateCallback onMouseDragUpdate;
  final VoidCallback onMouseDragEnd;
  final VoidCallback onMouseDragCancel;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      skipTraversal: true,
      onKeyEvent: onKeyEvent,
      child: RawGestureDetector(
        gestures: {
          PanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                () => PanGestureRecognizer(
                  supportedDevices: const {PointerDeviceKind.mouse},
                ),
                (recognizer) {
                  // 锚点必须是**按下**位置：默认的 DragStartBehavior.start 报的是
                  // 「拖动被识别时」的位置，选区起点会跳到超过 slop 之后那一点，
                  // 且触发识别的那段位移会被并入 onStart 而收不到 onUpdate。
                  recognizer.dragStartBehavior = DragStartBehavior.down;
                  recognizer.onStart = onMouseDragStart;
                  recognizer.onUpdate = onMouseDragUpdate;
                  recognizer.onEnd = (_) => onMouseDragEnd();
                  recognizer.onCancel = onMouseDragCancel;
                },
              ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onTapUp,
          onLongPressStart: onLongPressStart,
          onLongPressMoveUpdate: onLongPressMoveUpdate,
          onLongPressEnd: onLongPressEnd,
          // 桌面：文字上显示 I-beam 光标（`SelectableText` 自带，自有实现要自己给）。
          child: MouseRegion(cursor: SystemMouseCursors.text, child: child),
        ),
      ),
    );
  }
}
