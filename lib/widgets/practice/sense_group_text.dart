/// 意群标注文本组件
///
/// 将句子按意群渲染为内联 badge 样式，保持自然文本排版。
/// 所有意群使用统一背景色，可点击播放对应音频片段。
/// 支持四种视觉状态：空闲 / 播放中 / 已播放 / 已收藏。
///
/// 已收藏的单词/词组在 badge 内文本上渲染橙色点状下划线（与
/// [SelectableSentenceText] 同一套匹配逻辑与视觉语言），纯视觉、
/// 不改变点击播放意群的交互；badge 本体即已收藏意群（橙底+边框）时，
/// 整段自匹配不重复下划线，只标记内部更细粒度的收藏词/词组。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/speech_practice_models.dart';
import '../../providers/saved_word_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/saved_text_index.dart';
import '../../utils/sense_group_timing.dart';
import '../common/text_context_menu.dart';
import 'sentence_word_selection.dart';

/// 跟读匹配单词的高亮色（与非意群模式 [SentenceAnnotationCard] 保持一致）
const _matchedColor = Color(0xFF2E9B51);

/// 提取英文单词（与 [SpeechTranscriptMatcher] 规则一致，保留撇号）
final _englishWordPattern = RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?");

/// 意群 badge 空闲态背景色（亮色主题）
///
/// 用中性灰，搭配跟读完成后的绿色匹配字，也避免蓝底误导用户。
const _groupColorLight = Color(0xFFEDEFF2); // 中性浅灰

/// 意群 badge 空闲态背景色（暗色主题）
const _groupColorDark = Color(0xFF26262A); // 中性深灰

/// 播放中意群背景色（暗色主题）
///
/// 比空闲态更亮一档的实色蓝，凸显"正在播放"；替代 M3 primaryContainer
/// （低饱和灰蓝在纯黑上发雾），与空闲态保持同色系。
const _playingColorDark = Color(0xFF1E4A70); // 亮蓝（播放中）

/// 已收藏意群背景色（亮色主题）
final _savedColorLight = Colors.orange.shade50;

/// 已收藏意群背景色（暗色主题）
final _savedColorDark = Colors.orange.shade900.withValues(alpha: 0.2);

/// 已收藏意群边框色
final _savedBorderColor = Colors.orange.shade300;

/// 归一化意群文本（小写 + trim + 去句末标点，保留撇号）
///
/// 与 DAO 层的归一化规则保持一致。
String normalizeSenseGroupPhrase(String text) {
  return text.trim().toLowerCase().replaceAll(RegExp(r'[.!?,;:]+$'), '');
}

/// 意群标注文本
///
/// 使用 Wrap + badge 实现，意群间留出间距，意群内单词保持正常间距。
class SenseGroupText extends ConsumerStatefulWidget {
  /// 意群文本列表
  final List<String> chunks;

  /// 各意群时间范围
  final List<SenseGroupTiming> timings;

  /// 正在播放的意群索引（null 表示无播放）
  final int? playingGroupIndex;

  /// 已播放过的意群索引集合
  final Set<int> playedGroupIndices;

  /// 点击意群回调（播放）
  final void Function(int groupIndex) onTapGroup;

  /// 点击意群回调（附带 badge 全局位置，用于显示工具条）
  final void Function(int groupIndex, Rect globalRect)? onTapGroupWithRect;

  /// 已收藏的意群文本集合（归一化后）
  final Set<String> savedGroupTexts;

  /// 跟读完成后的词级匹配片段（覆盖整句，按顺序）
  ///
  /// 为 null 或空时不做单词高亮，意群 badge 用纯文本渲染。
  final List<SpeechTranscriptSegment>? highlightedSegments;

  const SenseGroupText({
    super.key,
    required this.chunks,
    required this.timings,
    this.playingGroupIndex,
    this.playedGroupIndices = const {},
    required this.onTapGroup,
    this.onTapGroupWithRect,
    this.savedGroupTexts = const {},
    this.highlightedSegments,
  });

  @override
  ConsumerState<SenseGroupText> createState() => _SenseGroupTextState();
}

class _SenseGroupTextState extends ConsumerState<SenseGroupText> {
  /// 每个 badge 的 GlobalKey，用于获取位置
  final List<GlobalKey> _badgeKeys = [];

  @override
  void didUpdateWidget(SenseGroupText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBadgeKeys();
  }

  @override
  void initState() {
    super.initState();
    _syncBadgeKeys();
  }

  void _syncBadgeKeys() {
    while (_badgeKeys.length < widget.chunks.length) {
      _badgeKeys.add(GlobalKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseStyle = theme.textTheme.titleMedium?.copyWith(
      height: 1.4,
      color: colorScheme.onSurface,
    );

    // 收藏索引流式监听：加载中/降级（测试环境无 DB）时为空索引 = 无标记
    final savedMasks = _buildSavedMasks(ref.watch(savedTextIndexProvider));
    final savedColor = AppTheme.savedTextMarkColor(theme.brightness);

    // 按 chunk 顺序预生成高亮 span（单词游标跨 badge 连续消费）
    final chunkSpans = _buildChunkSpans(savedMasks, savedColor);

    return Wrap(
      // 与讲解工具栏使用同一紧凑间距，保证意群换行后横纵留白一致。
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        for (var i = 0; i < widget.chunks.length; i++)
          _buildGroupBadge(
            i,
            baseStyle,
            colorScheme,
            chunkSpans?[i],
            savedMasks[i],
            savedColor,
          ),
      ],
    );
  }

  /// 各意群的收藏命中掩码（下标与 [SenseGroupText.chunks] 对齐；空列表 = 无命中）
  ///
  /// badge 本体即已收藏意群时剔除「整段自匹配」区间——收藏态已由
  /// 橙底+边框表达，整段下划线只会叠加噪声；内部更细的收藏词/词组照标。
  List<List<bool>> _buildSavedMasks(SavedTextIndex index) {
    return [for (final chunk in widget.chunks) _savedMaskFor(chunk, index)];
  }

  List<bool> _savedMaskFor(String chunk, SavedTextIndex index) {
    if (index.isEmpty) return const [];
    final text = chunk.trim();
    var ranges = savedCharRanges(text, tokenizeSentence(text), index);
    if (ranges.isEmpty) return const [];
    if (widget.savedGroupTexts.contains(normalizeSenseGroupPhrase(chunk))) {
      final fullSpan = trimSavedRange(text, 0, text.length);
      ranges = [
        for (final range in ranges)
          if (range != fullSpan) range,
      ];
      if (ranges.isEmpty) return const [];
    }
    return charMaskFromRanges(text.length, ranges);
  }

  /// 把 [start, end) 按收藏掩码切成子 span：命中子段加点状下划线，
  /// 可选叠加跟读匹配文字色 [color]（下划线与染色正交可叠加）
  List<InlineSpan> _savedAwareSpans(
    String text,
    int start,
    int end,
    List<bool> mask,
    Color savedColor, {
    Color? color,
  }) {
    return [
      for (final (subStart, subEnd, saved) in splitByMask(start, end, mask))
        TextSpan(
          text: text.substring(subStart, subEnd),
          style: (color == null && !saved)
              ? null
              : TextStyle(
                  color: color,
                  decoration: saved ? TextDecoration.underline : null,
                  decorationStyle: saved ? TextDecorationStyle.dotted : null,
                  decorationColor: saved ? savedColor : null,
                  decorationThickness: saved ? 2 : null,
                ),
        ),
    ];
  }

  /// 把高亮片段拍平为有序的单词匹配标志列表。
  ///
  /// 单词段产出一个标志（其 isMatched），间隔段（空白/标点）不产出。
  /// 无高亮数据时返回 null。
  List<bool>? _buildWordFlags() {
    final segments = widget.highlightedSegments;
    if (segments == null || segments.isEmpty) {
      return null;
    }
    final flags = <bool>[];
    for (final segment in segments) {
      for (final _ in _englishWordPattern.allMatches(segment.text)) {
        flags.add(segment.isMatched);
      }
    }
    return flags;
  }

  /// 按 chunk 顺序生成每个意群的富文本 span，单词游标连续消费 [_buildWordFlags]；
  /// 各子段同时按 [savedMasks] 叠加收藏下划线。
  ///
  /// 无高亮数据时返回 null（badge 回退为纯文本/收藏下划线文本）。
  List<List<InlineSpan>>? _buildChunkSpans(
    List<List<bool>> savedMasks,
    Color savedColor,
  ) {
    final wordFlags = _buildWordFlags();
    if (wordFlags == null) {
      return null;
    }

    var wordCursor = 0;
    final result = <List<InlineSpan>>[];
    for (var ci = 0; ci < widget.chunks.length; ci++) {
      final text = widget.chunks[ci].trim();
      final mask = savedMasks[ci];
      final spans = <InlineSpan>[];
      // 与普通模式一致：只给纯英文单词上色，单词外字符（空格/标点/连字符）原样保留
      var last = 0;
      for (final match in _englishWordPattern.allMatches(text)) {
        if (match.start > last) {
          spans.addAll(
            _savedAwareSpans(text, last, match.start, mask, savedColor),
          );
        }
        // 按单词顺序消费匹配标志，越界按未匹配处理
        final isMatched =
            wordCursor < wordFlags.length && wordFlags[wordCursor];
        wordCursor++;
        spans.addAll(
          _savedAwareSpans(
            text,
            match.start,
            match.end,
            mask,
            savedColor,
            color: isMatched ? _matchedColor : null,
          ),
        );
        last = match.end;
      }
      if (last < text.length) {
        spans.addAll(
          _savedAwareSpans(text, last, text.length, mask, savedColor),
        );
      }
      result.add(spans);
    }
    return result;
  }

  /// 构建单个意群 badge
  ///
  /// [highlightSpans] 非空时按词级匹配渲染富文本（已含收藏下划线）；
  /// 否则用纯文本，[savedMask] 非空时按掩码叠加收藏下划线。
  Widget _buildGroupBadge(
    int index,
    TextStyle? baseStyle,
    ColorScheme colorScheme,
    List<InlineSpan>? highlightSpans,
    List<bool> savedMask,
    Color savedColor,
  ) {
    final chunk = widget.chunks[index];
    final isPlaying = widget.playingGroupIndex == index;
    final isPlayed = widget.playedGroupIndices.contains(index);
    final isSaved = widget.savedGroupTexts.contains(
      normalizeSenseGroupPhrase(chunk),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 背景色优先级：播放中 > 已收藏 > 默认
    final Color bgColor;
    if (isPlaying) {
      bgColor = isDark ? _playingColorDark : colorScheme.primaryContainer;
    } else if (isSaved) {
      bgColor = isDark ? _savedColorDark : _savedColorLight;
    } else {
      bgColor = isDark ? _groupColorDark : _groupColorLight;
    }

    // 边框优先级：播放中 > 已收藏 > 已播放 > 默认
    final Color borderColor;
    if (isPlaying) {
      borderColor = colorScheme.primary;
    } else if (isSaved) {
      borderColor = _savedBorderColor;
    } else if (isPlayed) {
      borderColor = colorScheme.primary.withValues(alpha: 0.3);
    } else {
      borderColor = colorScheme.outline.withValues(alpha: 0.3);
    }
    final border = Border.all(color: borderColor, width: 1.5);

    return GestureDetector(
      onTap: () {
        widget.onTapGroup(index);
        // 获取 badge 全局位置，通知父组件显示工具条
        if (widget.onTapGroupWithRect != null) {
          final renderBox =
              _badgeKeys[index].currentContext?.findRenderObject()
                  as RenderBox?;
          if (renderBox != null) {
            final position = renderBox.localToGlobal(Offset.zero);
            final rect = position & renderBox.size;
            widget.onTapGroupWithRect!(index, rect);
          }
        }
      },
      onLongPressStart: (details) =>
          TextContextMenu.show(context, details.globalPosition, chunk.trim()),
      onSecondaryTapDown: (details) =>
          TextContextMenu.show(context, details.globalPosition, chunk.trim()),
      child: Container(
        key: _badgeKeys[index],
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: border,
        ),
        child: highlightSpans != null
            ? RichText(
                text: TextSpan(style: baseStyle, children: highlightSpans),
              )
            : savedMask.isEmpty
            ? Text(chunk.trim(), style: baseStyle)
            : Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: _savedAwareSpans(
                    chunk.trim(),
                    0,
                    chunk.trim().length,
                    savedMask,
                    savedColor,
                  ),
                ),
              ),
      ),
    );
  }
}
