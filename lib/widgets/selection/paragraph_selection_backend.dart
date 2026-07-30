/// 单段文本的选区后端（L3 实现）
///
/// 基于 [RenderParagraph] 的公开几何 API：`getPositionForOffset` 命中、
/// `getBoxesForSelection` 取矩形。高亮矩形用 `BoxHeightStyle.tight` 贴字形——
/// 这是 `Selectable` 协议做不到的（协议内部硬编码 `BoxHeightStyle.max`，
/// 见 `rendering/paragraph.dart`），也是自己拥有几何的主要收益。
///
/// 与 [MultiParagraphSelectionBackend] 的分工：本实现的字符空间**由调用方给定**
/// （`text`），因此查词业务的分词偏移与渲染 span 严格同源；跨块场景无法做到这点，
/// 只能由后端拼接段落纯文本。
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'selection_backend.dart';

/// 单段 [RenderParagraph] 的选区后端。
///
/// [paragraph] 每次调用时惰性取值：渲染节点会随重建换实例，不能缓存。
class ParagraphSelectionBackend implements SelectionBackend {
  ParagraphSelectionBackend({
    required RenderParagraph? Function() paragraph,
    required String Function() text,
    required WordRangeResolver wordRange,
  }) : _paragraph = paragraph,
       _text = text,
       _wordRange = wordRange;

  final RenderParagraph? Function() _paragraph;
  final String Function() _text;
  final WordRangeResolver _wordRange;

  /// 点词命中的矩形外扩容差（dp）：字形边缘 1~2px 的误差不该让点词失效。
  static const double _kHitSlop = 2;

  RenderParagraph? get _ready {
    final para = _paragraph();
    if (para == null || !para.attached || !para.hasSize) return null;
    return para;
  }

  @override
  RenderBox? get contentBox => _ready;

  @override
  bool get isReady => _ready != null;

  @override
  int get contentLength => _text().length;

  @override
  ui.TextRange? wordAt(Offset globalPosition) {
    final para = _ready;
    if (para == null) return null;
    final local = para.globalToLocal(globalPosition);
    final position = para.getPositionForOffset(local);
    final range = wordAtCharOffset(position.offset);
    if (range == null) return null;
    // 矩形包含判定：防止点行尾空白区域反查到最近的词而误触发。
    final boxes = para.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    final hit = boxes.any(
      (box) => box.toRect().inflate(_kHitSlop).contains(local),
    );
    return hit ? range : null;
  }

  @override
  ui.TextRange? wordAtCharOffset(int charOffset) {
    // 光标位可能落在词的右边界（== end），前移一位再判定。
    final range = _wordRange(charOffset);
    if (range != null) return range;
    return charOffset > 0 ? _wordRange(charOffset - 1) : null;
  }

  @override
  int? offsetAt(Offset globalPosition) {
    final para = _ready;
    if (para == null) return null;
    return para.getPositionForOffset(para.globalToLocal(globalPosition)).offset;
  }

  @override
  List<Rect> highlightRects(ui.TextRange range) {
    final para = _ready;
    if (para == null || !range.isValid || range.isCollapsed) return const [];
    return para
        .getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
          // 贴字形：默认会把行高的额外 leading 算进高亮，造成文字与选区中线错位。
          boxHeightStyle: ui.BoxHeightStyle.tight,
        )
        .map((box) => box.toRect())
        .toList(growable: false);
  }

  @override
  (Rect, Rect)? handleAnchors(ui.TextRange range) {
    final para = _ready;
    if (para == null || !range.isValid || range.isCollapsed) return null;
    // 锚点用默认（max）高度：手柄竖线应覆盖整行高，与平台手柄的 textLineHeight
    // 语义一致；高亮才需要 tight。
    final boxes = para.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    if (boxes.isEmpty) return null;
    return (boxes.first.toRect(), boxes.last.toRect());
  }

  @override
  Rect? caretRectAt(int charOffset) {
    final para = _ready;
    if (para == null) return null;
    final position = ui.TextPosition(
      offset: charOffset.clamp(0, contentLength),
    );
    final origin = para.getOffsetForCaret(position, Rect.zero);
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      0,
      para.getFullHeightForCaret(position),
    );
  }

  @override
  String textIn(ui.TextRange range) {
    final text = _text();
    if (!range.isValid) return '';
    final start = range.start.clamp(0, text.length);
    final end = range.end.clamp(start, text.length);
    return text.substring(start, end);
  }
}
