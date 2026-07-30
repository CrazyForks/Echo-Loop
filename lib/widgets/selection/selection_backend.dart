/// 选区后端抽象（L3）：命中测试、词边界、几何与取文本
///
/// 这一层是「内容形状」的唯一差异点：单段纯文本可以直接用一个 [RenderParagraph]
/// 的字符偏移与矩形（[ParagraphSelectionBackend]）；由 markdown 渲染出的多个块
/// 则要把若干段落拼成一个连续的字符空间（[MultiParagraphSelectionBackend]）。
/// 上层的会话语义（L1）与呈现（L2）对两者完全相同，因此差异收敛在本接口后面。
///
/// 命名为 backend 而非 geometry：它不只算矩形，还负责命中、词边界与取文本。
///
/// 坐标约定：入参的位置一律是**全局坐标**，返回的矩形一律是 [contentBox] 的
/// **局部坐标**。呈现层（高亮画笔、手柄、放大镜、操作条锚点）全部以 [contentBox]
/// 为参照系，所以组装件必须保证「画高亮的那层」与 [contentBox] 原点一致。
library;

import 'package:flutter/rendering.dart';

/// 词边界策略：给定字符偏移，返回该处「词」的字符区间；不在词内返回 null。
///
/// 由调用方注入——查词场景必须用**词典自己的分词规则**，不能用平台 ICU 边界
/// （ICU 会把 `co-op` 断成 `co`/`-`/`op`、`e.g.` 断成 `e`/`.`/`g`，导致高亮的
/// 词与查询、收藏用的词不是同一个）。不注入时由后端用所在段落的 ICU 边界兜底
/// （AI 回答等无业务分词的场景，ICU 反而能正确切分中文）。
typedef WordRangeResolver = TextRange? Function(int charOffset);

/// 单一内容的选区后端。
abstract interface class SelectionBackend {
  /// 内容盒：几何参照系，也是「选区是否还在视口内」与操作条锚点的换算基准。
  ///
  /// 未挂载或未布局时返回 null。
  RenderBox? get contentBox;

  /// 后端当前是否可用（渲染节点已 attach 且已布局）。
  bool get isReady;

  /// 可选区文本总长度（键盘扩选时钳制边界）。
  int get contentLength;

  /// 全局坐标 → 该处「词」的字符区间；点在空白/标点上返回 null。
  ///
  /// 实现需要做**矩形包含判定**，否则点行尾空白会反查到最近的词而误触发。
  TextRange? wordAt(Offset globalPosition);

  /// 字符偏移 → 该处「词」的字符区间（词粒度拖选、双击选词用）。
  TextRange? wordAtCharOffset(int charOffset);

  /// 全局坐标 → 字符偏移（拖手柄扩选用）；不可用时返回 null。
  int? offsetAt(Offset globalPosition);

  /// 字符区间 → 高亮矩形（[contentBox] 局部坐标，贴字形）。
  List<Rect> highlightRects(TextRange range);

  /// 字符区间 → 首尾锚点矩形（[contentBox] 局部坐标，高度为行高，供手柄定位）。
  ///
  /// 返回 `(起始锚点, 结束锚点)`；区间不可解析时返回 null。
  (Rect, Rect)? handleAnchors(TextRange range);

  /// 字符偏移 → 该处光标竖线矩形（[contentBox] 局部坐标，宽 0、高为行高）。
  ///
  /// 键盘上下行扩选据此换算相邻行的位置，避免上层依赖行结构。
  Rect? caretRectAt(int charOffset);

  /// 字符区间 → 选中文本。
  String textIn(TextRange range);
}
