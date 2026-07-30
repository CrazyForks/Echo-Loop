/// 扩选算术与点击节奏（L2 的无状态部分）
///
/// 从内核里分出来的都是**不依赖 widget** 的计算：固定端 + 浮动端怎么变成字符区间、
/// 相邻行的同列位置在哪、两次点击算不算双击。放在这里可以单独单测，内核只留语义。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'selection_backend.dart';

/// 长按拖选是否按**词**粒度扩选。
///
/// 对齐平台文本选择行为：Android / Fuchsia / Linux / Windows 的长按拖动按词扩选
/// （框架内部走 `selectWordsInRange`），iOS / macOS 按字符（`selectPositionAt`）。
/// 手柄拖拽在所有平台都是字符级。
bool longPressSelectsWords(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => false,
  _ => true,
};

/// 由固定端 [base] 与浮动端 [offset] 组成区间。
///
/// [wordGranularity] 为 true 时两端扩到所在词的边界（词边界来自后端注入的分词
/// 规则，不用平台 ICU 边界）。
TextRange rangeBetween(
  SelectionBackend backend,
  int base,
  int offset, {
  required bool wordGranularity,
}) {
  var start = base < offset ? base : offset;
  var end = base < offset ? offset : base;
  if (wordGranularity) {
    final startWord = backend.wordAtCharOffset(start);
    if (startWord != null && startWord.start < start) start = startWord.start;
    final endWord = backend.wordAtCharOffset(end > 0 ? end - 1 : end);
    if (endWord != null && endWord.end > end) end = endWord.end;
  }
  return TextRange(start: start, end: end);
}

/// 区间里「浮动端」的偏移：固定端 [base] 的对端。
int extentOf(TextRange range, int base) =>
    base <= range.start ? range.end : range.start;

/// 相邻行中与 [offset] 同列的字符偏移（Shift+↑/↓ 用）；不可解析返回 null。
///
/// 走光标几何而不是行结构：上层不需要知道换行在哪，跨块后端也能跨到相邻块。
int? offsetInAdjacentLine(SelectionBackend backend, int offset, int direction) {
  final box = backend.contentBox;
  final caret = backend.caretRectAt(offset);
  if (box == null || caret == null) return null;
  final target = Offset(
    caret.center.dx,
    caret.center.dy + direction * caret.height,
  );
  return backend.offsetAt(box.localToGlobal(target));
}

/// 点击节奏：自行判定双击。
///
/// **不用** [DoubleTapGestureRecognizer]：它会 hold 住手势竞技场，单击要等双击
/// 超时（约 300ms）才生效，点词查词整体变迟钝。
class TapCadence {
  DateTime? _lastTime;
  Offset? _lastPosition;

  /// [position] 处的这次点击是否构成双击（需在时间窗与 slop 内）。
  bool isDoubleTap(Offset position, {DateTime? now}) {
    final time = _lastTime;
    final last = _lastPosition;
    if (time == null || last == null) return false;
    return (now ?? DateTime.now()).difference(time) < kDoubleTapTimeout &&
        (position - last).distance <= kDoubleTapSlop;
  }

  /// 记录本次点击（每次 tap 都要记，无论是否双击）。
  void record(Offset position, {DateTime? now}) {
    _lastTime = now ?? DateTime.now();
    _lastPosition = position;
  }
}
