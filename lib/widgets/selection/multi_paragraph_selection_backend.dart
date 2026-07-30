/// 跨块文本的选区后端（L3 实现）
///
/// 用于 markdown 这类「一段内容渲染成多个 [RenderParagraph]」的场景（AI 回答）。
/// 做法是把容器子树里的段落按**文档顺序**拼成一个连续字符空间，于是 L1 会话与
/// L2 呈现完全不需要知道「跨块」这件事。
///
/// **文档顺序怎么来**：`gpt_markdown` 把整段内容渲染成一个根 `RichText`，块级元素
/// （标题、列表、引用、表格）以 `WidgetSpan` 占位符嵌在其中，占位符里又是新的
/// `RichText`（可多层）。所以顺序不能靠「渲染树里遇到的先后」，必须**按占位符在
/// span 中的位置递归**：段落自己的文本被占位符切成若干段，占位符处插入子块的段。
/// [RenderParagraph] 的占位符子节点顺序与 span 中的出现顺序一致，因此下标即对应。
///
/// **为什么不用 `SelectionContainer` + `Selectable` 协议**（Flutter 官方跨块选区）：
/// - 协议内部把高亮矩形硬编码为 `BoxHeightStyle.max`（`rendering/paragraph.dart`），
///   跨块高亮必然带行高 leading；自己走段落几何可以继续用 tight，与单段一致；
/// - 官方 `SelectableRegion` 会在**失焦时清空选区**，而本项目要求选区跨越面板
///   交互存活（见 CLAUDE.md §7.28），照搬其手势 → `SelectionEvent` 派发只会把
///   那份契约一起搬进来；
/// - markdown 流式渲染时子节点频繁增删，官方 selectable 注册表会在帧末重入
///   （历史上的 `ConcurrentModificationError`）。本实现不注册任何东西，只在需要时
///   读一遍渲染树。
///
/// 代价：段落之外的内容（图片、分隔线等纯装饰）不参与选区。
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'selection_backend.dart';

/// `WidgetSpan` 在纯文本里占的码位（[PlaceholderSpan.placeholderCodeUnit]）。
const int _kPlaceholderCodeUnit = 0xFFFC;

/// 扁平字符空间中的一段：某个段落的一段连续文本。
///
/// 一个段落会被它内部的占位符切成多段，因此段落与段不是一对一。
class _Segment {
  _Segment({
    required this.paragraph,
    required this.localStart,
    required this.base,
    required this.text,
  });

  final RenderParagraph paragraph;

  /// 本段在**段落自身文本空间**（含占位符码位）中的起点。几何 API 用这个空间。
  final int localStart;

  /// 本段在扁平字符空间中的起点。
  final int base;

  /// 本段文本（不含占位符）。
  final String text;

  int get end => base + text.length;

  int get localEnd => localStart + text.length;

  /// 扁平偏移 → 段落局部偏移。
  int localOffsetOf(int flatOffset) =>
      localStart + (flatOffset.clamp(base, end) - base);

  /// 段落局部偏移 → 扁平偏移。
  int flatOffsetOf(int localOffset) =>
      base + (localOffset.clamp(localStart, localEnd) - localStart);

  /// 段落局部坐标 → 容器局部坐标的变换。
  Matrix4 transformTo(RenderBox container) =>
      paragraph.getTransformTo(container);
}

/// 跨块选区后端：把容器子树内的段落拼成单一字符空间。
///
/// [container] 惰性取值：渲染节点随重建换实例，不能缓存。段落列表也每次现算——
/// 一条 AI 回答的子树只有几十个节点，遍历开销远小于维护缓存失效的复杂度。
class MultiParagraphSelectionBackend implements SelectionBackend {
  MultiParagraphSelectionBackend({
    required RenderBox? Function() container,
    WordRangeResolver? wordRange,
  }) : _container = container,
       _wordRange = wordRange;

  final RenderBox? Function() _container;

  /// 词边界策略；为空时用所在段落的 ICU 边界（能正确切分中日韩文本）。
  final WordRangeResolver? _wordRange;

  /// 点词命中的矩形外扩容差（dp），与单段后端一致。
  static const double _kHitSlop = 2;

  RenderBox? get _readyContainer {
    final box = _container();
    if (box == null || !box.attached || !box.hasSize) return null;
    return box;
  }

  @override
  RenderBox? get contentBox => _readyContainer;

  @override
  bool get isReady => _segments().isNotEmpty;

  @override
  int get contentLength {
    final segments = _segments();
    return segments.isEmpty ? 0 : segments.last.end;
  }

  // -- 扁平字符空间 --

  /// 按文档顺序切分段落，生成扁平字符空间。
  List<_Segment> _segments() {
    final container = _readyContainer;
    if (container == null) return const [];
    final segments = <_Segment>[];
    var base = 0;

    void addSegment(RenderParagraph paragraph, int localStart, String text) {
      if (text.isEmpty) return;
      // 两段之间既没有换行也没有空白时补一个换行（如表格相邻单元格），
      // 保证跨块复制的文本可读；这个换行占扁平空间的一个偏移，不属于任何段。
      if (segments.isNotEmpty &&
          !_endsWithBreak(segments.last.text) &&
          !_startsWithBreak(text)) {
        base += 1;
      }
      segments.add(
        _Segment(
          paragraph: paragraph,
          localStart: localStart,
          base: base,
          text: text,
        ),
      );
      base += text.length;
    }

    void visitNode(RenderObject node) {
      if (node is! RenderParagraph) {
        node.visitChildren(visitNode);
        return;
      }
      if (!node.attached || !node.hasSize) return;
      final full = node.text.toPlainText(includeSemanticsLabels: false);
      final children = <RenderObject>[];
      node.visitChildren(children.add);
      var cursor = 0;
      var childIndex = 0;
      for (var i = 0; i < full.length; i++) {
        if (full.codeUnitAt(i) != _kPlaceholderCodeUnit) continue;
        addSegment(node, cursor, full.substring(cursor, i));
        // 占位符处插入子块（顺序与 span 中的占位符顺序一致）。
        if (childIndex < children.length) visitNode(children[childIndex]);
        childIndex++;
        cursor = i + 1;
      }
      addSegment(node, cursor, full.substring(cursor));
    }

    visitNode(container);
    return segments;
  }

  static bool _endsWithBreak(String text) =>
      text.isEmpty || _isBreak(text.codeUnitAt(text.length - 1));

  static bool _startsWithBreak(String text) =>
      text.isEmpty || _isBreak(text.codeUnitAt(0));

  static bool _isBreak(int codeUnit) =>
      codeUnit == 0x0A || codeUnit == 0x20 || codeUnit == 0x09;

  /// 扁平文本；段之间的空隙（补的换行）按换行填充。
  String _flatText(List<_Segment> segments) {
    final buffer = StringBuffer();
    for (final segment in segments) {
      while (buffer.length < segment.base) {
        buffer.write('\n');
      }
      buffer.write(segment.text);
    }
    return buffer.toString();
  }

  // -- 命中与词边界 --

  @override
  ui.TextRange? wordAt(Offset globalPosition) {
    final segments = _segments();
    final segment = _segmentAt(segments, globalPosition, requireHit: true);
    if (segment == null) return null;
    final local = segment.paragraph.globalToLocal(globalPosition);
    final position = segment.paragraph.getPositionForOffset(local);
    final range = wordAtCharOffset(segment.flatOffsetOf(position.offset));
    if (range == null) return null;
    // 矩形包含判定：点在行尾空白处不该反查到最近的词。
    final hit = _rectsIn(
      segment,
      range,
    ).any((rect) => rect.inflate(_kHitSlop).contains(local));
    return hit ? range : null;
  }

  @override
  ui.TextRange? wordAtCharOffset(int charOffset) {
    final resolver = _wordRange;
    if (resolver != null) {
      final range = resolver(charOffset);
      if (range != null) return range;
      return charOffset > 0 ? resolver(charOffset - 1) : null;
    }
    final segments = _segments();
    final segment = _segmentOfOffset(segments, charOffset);
    if (segment == null) return null;
    var local = segment.localOffsetOf(charOffset);
    // 偏移可能落在词的右边界（== end），前移一位再判定。
    if (local >= segment.localEnd && local > segment.localStart) local -= 1;
    final word = segment.paragraph.getWordBoundary(
      ui.TextPosition(offset: local),
    );
    if (!word.isValid || word.isCollapsed) return null;
    // 词边界不能越过本段（段落里占位符两侧属于不同的块）。
    final start = segment.flatOffsetOf(word.start);
    final end = segment.flatOffsetOf(word.end);
    return start >= end ? null : ui.TextRange(start: start, end: end);
  }

  @override
  int? offsetAt(Offset globalPosition) {
    final segments = _segments();
    final segment = _segmentAt(segments, globalPosition, requireHit: false);
    if (segment == null) return null;
    final local = segment.paragraph.globalToLocal(globalPosition);
    final position = segment.paragraph.getPositionForOffset(local);
    return segment.flatOffsetOf(position.offset);
  }

  // -- 几何 --

  @override
  List<Rect> highlightRects(ui.TextRange range) {
    if (!range.isValid || range.isCollapsed) return const [];
    final container = _readyContainer;
    if (container == null) return const [];
    final rects = <Rect>[];
    for (final segment in _segments()) {
      final transform = segment.transformTo(container);
      for (final rect in _rectsIn(segment, range, tight: true)) {
        rects.add(MatrixUtils.transformRect(transform, rect));
      }
    }
    return rects;
  }

  @override
  (Rect, Rect)? handleAnchors(ui.TextRange range) {
    if (!range.isValid || range.isCollapsed) return null;
    final container = _readyContainer;
    if (container == null) return null;
    Rect? first;
    Rect? last;
    for (final segment in _segments()) {
      final boxes = _rectsIn(segment, range);
      if (boxes.isEmpty) continue;
      final transform = segment.transformTo(container);
      first ??= MatrixUtils.transformRect(transform, boxes.first);
      last = MatrixUtils.transformRect(transform, boxes.last);
    }
    if (first == null || last == null) return null;
    return (first, last);
  }

  @override
  Rect? caretRectAt(int charOffset) {
    final container = _readyContainer;
    if (container == null) return null;
    final segment = _segmentOfOffset(_segments(), charOffset);
    if (segment == null) return null;
    final position = ui.TextPosition(offset: segment.localOffsetOf(charOffset));
    final origin = segment.paragraph.getOffsetForCaret(position, Rect.zero);
    final caret = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      0,
      segment.paragraph.getFullHeightForCaret(position),
    );
    return MatrixUtils.transformRect(segment.transformTo(container), caret);
  }

  @override
  String textIn(ui.TextRange range) {
    if (!range.isValid) return '';
    final text = _flatText(_segments());
    final start = range.start.clamp(0, text.length);
    final end = range.end.clamp(start, text.length);
    return text.substring(start, end);
  }

  /// 扁平区间在某段内的矩形（段落局部坐标）；无交集返回空。
  List<Rect> _rectsIn(
    _Segment segment,
    ui.TextRange range, {
    bool tight = false,
  }) {
    final start = range.start > segment.base ? range.start : segment.base;
    final end = range.end < segment.end ? range.end : segment.end;
    if (start >= end) return const [];
    return segment.paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: segment.localOffsetOf(start),
            extentOffset: segment.localOffsetOf(end),
          ),
          boxHeightStyle: tight
              ? ui.BoxHeightStyle.tight
              : ui.BoxHeightStyle.max,
        )
        .map((box) => box.toRect())
        .toList(growable: false);
  }

  /// 本段自身文本的矩形（段落局部坐标），命中判定用。
  List<Rect> _boundsOf(_Segment segment) => segment.paragraph
      .getBoxesForSelection(
        TextSelection(
          baseOffset: segment.localStart,
          extentOffset: segment.localEnd,
        ),
      )
      .map((box) => box.toRect())
      .toList(growable: false);

  /// 偏移所属段；落在段间空隙时归属前一段。
  _Segment? _segmentOfOffset(List<_Segment> segments, int charOffset) {
    if (segments.isEmpty) return null;
    for (final segment in segments) {
      if (charOffset <= segment.end) return segment;
    }
    return segments.last;
  }

  /// 全局坐标所属段。
  ///
  /// 判定用**段自身的文本矩形**而不是段落的 box：块级元素是嵌套的（父段落的 box
  /// 覆盖子块），用 box 判定会命中外层。[requireHit] 为 false 时取最近的段（拖选
  /// 时手指可能停在块间空白或内容之外）。
  _Segment? _segmentAt(
    List<_Segment> segments,
    Offset globalPosition, {
    required bool requireHit,
  }) {
    _Segment? nearest;
    var nearestDistance = double.infinity;
    for (final segment in segments) {
      final local = segment.paragraph.globalToLocal(globalPosition);
      for (final rect in _boundsOf(segment)) {
        if (rect.inflate(_kHitSlop).contains(local)) return segment;
        final distance = _distanceToRect(rect, local);
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = segment;
        }
      }
    }
    return requireHit ? null : nearest;
  }

  static double _distanceToRect(Rect rect, Offset point) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : (point.dx > rect.right ? point.dx - rect.right : 0.0);
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : (point.dy > rect.bottom ? point.dy - rect.bottom : 0.0);
    // 竖直距离优先：文本自上而下排布，垂直方向的邻近才决定「拖到了哪一块」。
    return dy * 1000 + dx;
  }
}
