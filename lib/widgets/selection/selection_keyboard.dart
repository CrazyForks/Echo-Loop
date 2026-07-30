/// 键盘选区意图（L2）：按键 → 意图的纯映射
///
/// 拆成纯函数是为了能单测「哪些组合被消费」，而不必驱动整棵 widget 树。
/// 桌面才有键盘选区，移动端不会产生这些事件。
library;

import 'package:flutter/services.dart';

/// 键盘对选区的意图。
enum SelectionKeyIntent {
  /// 复制选区（Cmd/Ctrl+C）。平台标准：复制**保留**选区。
  copy,

  /// Shift+←：浮动端左移一个字符。
  extendCharacterLeft,

  /// Shift+→：浮动端右移一个字符。
  extendCharacterRight,

  /// Shift+↑：浮动端上移一行。
  extendLineUp,

  /// Shift+↓：浮动端下移一行。
  extendLineDown,
}

/// 把按键事件映射为选区意图；不相关的按键返回 null（不消费）。
///
/// 只处理按下与长按重复：抬起事件一律忽略，否则一次按键会被算两次。
SelectionKeyIntent? selectionKeyIntentFor(KeyEvent event) {
  if (event is KeyUpEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.keyC &&
      (keyboard.isMetaPressed || keyboard.isControlPressed)) {
    return SelectionKeyIntent.copy;
  }
  if (!keyboard.isShiftPressed) return null;
  return switch (key) {
    LogicalKeyboardKey.arrowLeft => SelectionKeyIntent.extendCharacterLeft,
    LogicalKeyboardKey.arrowRight => SelectionKeyIntent.extendCharacterRight,
    LogicalKeyboardKey.arrowUp => SelectionKeyIntent.extendLineUp,
    LogicalKeyboardKey.arrowDown => SelectionKeyIntent.extendLineDown,
    _ => null,
  };
}
