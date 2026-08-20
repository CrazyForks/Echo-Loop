/// 基于字幕句子生成近似词级时间戳。
///
/// 本地上传 SRT/VTT 没有真实词级时间戳。这里按每句字幕的起止时间，
/// 再按单词字符数占比分配每个词的时间，用于意群播放等需要词级时间的场景。
library;

import '../models/sentence.dart';
import '../models/word_timestamp.dart';
import '../services/subtitle_parser.dart';

final RegExp _wordPattern = RegExp(
  r'''[“"‘'(\[]*[A-Za-z0-9]+(?:'[A-Za-z0-9]+)?[A-Za-z0-9]*[.,!?;:)\]”"’'…-]*''',
);

/// 从 SRT 字符串生成近似词级时间戳。
///
/// 解析失败时沿用 [SubtitleParser.parseSubtitleString] 的容错语义，返回空列表。
Future<List<WordTimestamp>> generateSyntheticWordTimestampsFromSrt(
  String srt,
) async {
  final sentences = await SubtitleParser.parseSubtitleString(srt);
  return generateSyntheticWordTimestamps(sentences);
}

/// 从已解析字幕句子生成近似词级时间戳。
///
/// 每句内按单词字符数分配时间；撇号缩写作为同一个词，保留词面标点但不计入权重。
List<WordTimestamp> generateSyntheticWordTimestamps(List<Sentence> sentences) {
  final result = <WordTimestamp>[];
  for (final sentence in sentences) {
    result.addAll(_generateForSentence(sentence));
  }
  return result;
}

List<WordTimestamp> _generateForSentence(Sentence sentence) {
  final tokens = _extractWordTokens(sentence.text);
  if (tokens.isEmpty) return const [];

  final startMs = sentence.startTime.inMilliseconds;
  final endMs = sentence.endTime.inMilliseconds;
  final totalDurationMs = endMs - startMs;
  if (totalDurationMs <= 0) {
    return tokens
        .map(
          (token) => WordTimestamp(
            word: token.text,
            startTime: sentence.startTime,
            endTime: sentence.startTime,
          ),
        )
        .toList();
  }

  final totalWeight = tokens.fold<int>(0, (sum, token) => sum + token.weight);
  if (totalWeight <= 0) return const [];

  final words = <WordTimestamp>[];
  var currentMs = startMs;
  var consumedWeight = 0;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    consumedWeight += token.weight;

    // 用累计权重计算边界，避免逐词 round 误差累计导致最后一个词不能贴合句尾。
    final nextMs = i == tokens.length - 1
        ? endMs
        : startMs + (totalDurationMs * consumedWeight / totalWeight).round();

    words.add(
      WordTimestamp(
        word: token.text,
        startTime: Duration(milliseconds: currentMs),
        endTime: Duration(milliseconds: nextMs),
      ),
    );
    currentMs = nextMs;
  }
  return words;
}

List<_WordToken> _extractWordTokens(String text) {
  return _wordPattern
      .allMatches(text)
      .map((match) {
        final token = match.group(0)!;
        return _WordToken(token, _wordWeight(token));
      })
      .where((token) => token.weight > 0)
      .toList();
}

int _wordWeight(String token) {
  return token.replaceAll(RegExp(r"[^A-Za-z0-9]"), '').length;
}

class _WordToken {
  final String text;
  final int weight;

  const _WordToken(this.text, this.weight);
}
