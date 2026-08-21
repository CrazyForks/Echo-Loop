/// 从词典查询结果提取「可点击发音」的英文文本（供后台预热）
///
/// 词典弹窗里单词标题与每条例句都内嵌点击发音（`SpeakButton` / `_ExampleView`，
/// 见 `dictionary_panel.dart` 与 `ai_dict_result_view.dart`）。本函数把这些
/// 文本按弹窗显示顺序收齐，交给统一 TTS 后台预热入缓存，用户点击即命中秒播。
library;

import 'dictionary_lookup_result.dart';
import 'dictionary_entry.dart';

/// 提取 [result] 中所有可发音英文文本，按弹窗显示顺序：
/// 单词标题 → 各义项例句 → 常见搭配例句 → 词族例句。
///
/// 顺序与 `_AiEntryContent` 渲染顺序一致（最可能点击的靠前，便于预热优先命中）；
/// 空串剔除、保序去重（同句只预热一次）。本地 / 网页源无例句，仅单词标题可发音。
List<String> dictionarySpeakableTexts(DictionaryLookupResult result) {
  final texts = <String>[];

  // 单词标题（跨源恒有，标题行 SpeakButton 发此文本）。
  texts.add(result.headword);

  // AI 单词源带例句，且各例句均为 _ExampleView 的点击发音目标。
  if (result is AiDictResult) {
    switch (result.entry) {
      case final DictionaryEntry entry:
        for (final meaning in entry.meanings) {
          for (final ex in meaning.examples) {
            texts.add(ex.sentence);
          }
        }
        for (final expr in entry.commonExpressions) {
          texts.add(expr.example.sentence);
        }
        for (final item in entry.wordFamily) {
          texts.add(item.example.sentence);
        }
      case final MultiWordDictionaryEntry entry:
        for (final kp in entry.keyPoints) {
          texts.add(kp.sentence);
        }
        for (final meaning in entry.meanings) {
          for (final ex in meaning.examples) {
            texts.add(ex.sentence);
          }
        }
        for (final expr in entry.similarExpressions) {
          texts.add(expr.sentence);
        }
    }
  }

  // 空串剔除 + 保序去重。
  final seen = <String>{};
  final out = <String>[];
  for (final t in texts) {
    final trimmed = t.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(t)) out.add(t);
  }
  return out;
}

/// 返回词典结果中需要交给 TTS 后台预热的文本。
///
/// 标题已有离线发音时不进入 TTS 队列；AI 结果中的例句等文本始终保留。
/// 具体的预热调度仍由页面通过 `TtsController` 完成，避免本模型层依赖状态管理。
List<String> dictionaryPrewarmTexts(
  DictionaryLookupResult result, {
  required bool hasLocalClip,
}) {
  final texts = dictionarySpeakableTexts(result);
  if (hasLocalClip && texts.isNotEmpty) {
    return texts.skip(1).toList();
  }
  return texts;
}
