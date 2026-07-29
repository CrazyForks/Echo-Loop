/// 句内分词与收藏标记命中逻辑（供 SelectableSentenceText 使用，可独立单测）
///
/// 分词沿用标注卡既有正则 `\s+|[^\s]+`：把句子切成「空白段 / 非空白段」
/// 交替的 token 序列，并记录每个 token 在原文中的字符区间，
/// 供点词命中与收藏文本区间计算共用。
///
/// 另提供收藏词/词组/意群在句中的命中区间计算 [savedCharRanges]，
/// 供正文收藏标记（点状下划线）渲染使用。
library;

import '../../utils/saved_text_index.dart';
import '../../utils/text_normalize.dart';

/// 句内 token（带原文字符区间）
class WordToken {
  /// 在原文中的起始字符偏移（含）
  final int start;

  /// 在原文中的结束字符偏移（不含）
  final int end;

  /// 原始片段文本（词含标点，或纯空白）
  final String text;

  /// 是否为「词」：剥标点后仍含字母/数字（可作为查词单元）
  final bool isWord;

  const WordToken({
    required this.start,
    required this.end,
    required this.text,
    required this.isWord,
  });
}

/// 分词正则：空白段或非空白连续段（与标注卡既有实现一致）
final RegExp _tokenPattern = RegExp(r'\s+|[^\s]+');

/// 「词」判定：含至少一个字母或数字（纯标点段不可查词）
final RegExp _hasAlnum = RegExp(r'[A-Za-z0-9]');

/// 把句子切分为带字符偏移的 token 列表
List<WordToken> tokenizeSentence(String text) {
  return _tokenPattern
      .allMatches(text)
      .map(
        (m) => WordToken(
          start: m.start,
          end: m.end,
          text: m.group(0) ?? '',
          isWord:
              (m.group(0) ?? '').trim().isNotEmpty &&
              _hasAlnum.hasMatch(m.group(0) ?? ''),
        ),
      )
      .toList(growable: false);
}

/// 精确命中：字符偏移所在的 word token 索引；不在任何词内返回 -1。
///
/// 供点词判定使用（点空白/标点不触发查词，与吸附语义区分）。
int wordTokenAtChar(List<WordToken> tokens, int charOffset) {
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (charOffset >= t.start && charOffset < t.end) return t.isWord ? i : -1;
  }
  return -1;
}

/// 查询文本是否至少包含一个 Unicode 字母或数字。
///
/// 空白、标点和符号没有词典语义，不应创建或保留查词会话；内部包含标点的
/// 正常单词或词组仍视为有效，例如 `co-op`、`well, you know`。
bool hasDictionaryLookupContent(String text) {
  return trimSavedRange(text, 0, text.length) != null;
}

// -- 收藏词标记（正文点状下划线）命中计算 --

/// Unicode 字母/数字判定（区间修边用；比匹配侧的 ASCII 规则宽——修边只是
/// 显示裁剪，保留重音字母等词内字符，下划线不在词中间截断）
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// 各类撇号（直/弯/变体，与 [normalizeWord] 的撇号折叠集合一致）；
/// 修边时仅保留 `s'` 所有格尾撇号，引用尾引号不进入命中区间。
const String _apostrophes = "'’‘ʼ＇`´";

/// 收藏命中区间：索引中的收藏单词/词组/意群在 [text] 中命中的
/// 字符区间 [start, end) 列表。
///
/// 匹配两侧统一 [normalizeWord]（key 已在 [SavedTextIndex.build] 归一化，
/// 候选子串在此归一化），弯撇号/边缘标点/引号/多空格差异天然被折叠；
/// 词间夹标点（如 "figure, out"）归一化后仍保留内部标点，不会误报。
/// 窗口词数取索引实际条目词数、以句内词数为界，无静默丢弃。
///
/// 已知限制：收藏 key 是词典 lemma（如存 `run`），正文变形（`running`）
/// 归一化后不相等、不会命中（无现成词形→原形映射）。
List<(int, int)> savedCharRanges(
  String text,
  List<WordToken> tokens,
  SavedTextIndex index,
) {
  if (index.isEmpty) return const [];
  final wordIdx = <int>[
    for (var i = 0; i < tokens.length; i++)
      if (tokens[i].isWord) i,
  ];
  final ranges = <(int, int)>[];

  // 单词命中
  for (final i in wordIdx) {
    final t = tokens[i];
    if (index.singleWords.contains(normalizeWord(t.text))) {
      _addTrimmedRange(text, t.start, t.end, ranges);
    }
  }

  // 词组/意群命中：相邻 word token 滑动窗口
  for (final n in index.phraseWordCounts) {
    if (n > wordIdx.length) continue;
    for (var s = 0; s + n - 1 < wordIdx.length; s++) {
      final start = tokens[wordIdx[s]].start;
      final end = tokens[wordIdx[s + n - 1]].end;
      if (index.phrases.contains(normalizeWord(text.substring(start, end)))) {
        _addTrimmedRange(text, start, end, ranges);
      }
    }
  }
  return ranges;
}

/// 区间修边：两端剥非「字母/数字」字符，尾部 `s'` 撇号（直/弯）保留；
/// 修边后为空（纯标点）返回 null。
///
/// 公开供调用方识别「命中区间 == 整段文本修边区间」的自匹配
/// （如意群 badge 本体已有收藏视觉，整段命中不再重复下划线）。
(int, int)? trimSavedRange(String text, int start, int end) {
  var s = start;
  var e = end;
  while (s < e && !_letterOrDigit.hasMatch(text[s])) {
    s++;
  }
  while (e > s &&
      !_letterOrDigit.hasMatch(text[e - 1]) &&
      !_isPossessiveTrailingApostrophe(text, e - 1)) {
    e--;
  }
  return s < e ? (s, e) : null;
}

/// 判断 [index] 处撇号是否是 `dogs'` / `dogs’` 这类尾部所有格。
bool _isPossessiveTrailingApostrophe(String text, int index) {
  if (!_apostrophes.contains(text[index]) || index == 0) return false;
  return text[index - 1].toLowerCase() == 's';
}

/// 区间修边后加入结果（见 [trimSavedRange]）
void _addTrimmedRange(String text, int start, int end, List<(int, int)> out) {
  final trimmed = trimSavedRange(text, start, end);
  if (trimmed != null) out.add(trimmed);
}

/// 区间列表 → 逐字符标记掩码（供 span 按边界切分渲染）
List<bool> charMaskFromRanges(int length, List<(int, int)> ranges) {
  final mask = List<bool>.filled(length, false);
  for (final (start, end) in ranges) {
    for (var i = start; i < end && i < length; i++) {
      mask[i] = true;
    }
  }
  return mask;
}

/// 收藏命中按「空白分词」词序切分（逐词渲染场景用，如遮盖句子 Tile）。
///
/// 返回 `词序号 → 该词内按收藏命中边界切分的 (相对起, 相对止, 是否命中) 子段列表`。
/// 词序号与 `text.split(空白)` 的非空词序一致（即 keyword_extraction 的
/// tokenize 结果下标），子段偏移相对词首字符。无任何命中的词不出现在
/// 结果中，调用方可整词走普通渲染。
Map<int, List<(int, int, bool)>> savedWordSegments(
  String text,
  SavedTextIndex index,
) {
  if (index.isEmpty) return const {};
  final tokens = tokenizeSentence(text);
  final ranges = savedCharRanges(text, tokens, index);
  if (ranges.isEmpty) return const {};
  final mask = charMaskFromRanges(text.length, ranges);
  final result = <int, List<(int, int, bool)>>{};
  var wordIdx = 0;
  for (final t in tokens) {
    if (t.text.trim().isEmpty) continue; // 空白 token 不占词序
    final segments = splitByMask(t.start, t.end, mask);
    if (segments.any((s) => s.$3)) {
      result[wordIdx] = [
        for (final (subStart, subEnd, saved) in segments)
          (subStart - t.start, subEnd - t.start, saved),
      ];
    }
    wordIdx++;
  }
  return result;
}

/// 把字符区间 [start, end) 按掩码翻转点切成 (子段起, 子段止, 是否命中) 列表。
///
/// 掩码短于 [end] 时越界部分视为未命中（掩码可为空列表 = 全句无命中）。
List<(int, int, bool)> splitByMask(int start, int end, List<bool> mask) {
  bool flagAt(int i) => i < mask.length && mask[i];
  final result = <(int, int, bool)>[];
  var subStart = start;
  while (subStart < end) {
    final flag = flagAt(subStart);
    var subEnd = subStart + 1;
    while (subEnd < end && flagAt(subEnd) == flag) {
      subEnd++;
    }
    result.add((subStart, subEnd, flag));
    subStart = subEnd;
  }
  return result;
}
