/// 词级时间戳模型
///
/// 存储后端转录引擎（Deepgram/AssemblyAI）返回的每个单词的精确时间范围。
/// 用于意群播放时间映射。
library;

import 'dart:convert';

/// 单词时间戳
class WordTimestamp {
  /// 单词文本
  final String word;

  /// 开始时间
  final Duration startTime;

  /// 结束时间
  final Duration endTime;

  const WordTimestamp({
    required this.word,
    required this.startTime,
    required this.endTime,
  });

  /// 从后端 JSON 创建
  ///
  /// 后端 startTime / endTime 单位为秒（浮点数），需转换为 Duration。
  factory WordTimestamp.fromJson(Map<String, dynamic> json) {
    return WordTimestamp(
      word: json['word'] as String,
      startTime: Duration(
        milliseconds: ((json['startTime'] as num) * 1000).round(),
      ),
      endTime: Duration(
        milliseconds: ((json['endTime'] as num) * 1000).round(),
      ),
    );
  }

  /// 复制并替换部分字段。
  WordTimestamp copyWith({
    String? word,
    Duration? startTime,
    Duration? endTime,
  }) {
    return WordTimestamp(
      word: word ?? this.word,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
    'word': word,
    'startTime': startTime.inMilliseconds / 1000.0,
    'endTime': endTime.inMilliseconds / 1000.0,
  };
}

/// 将 WordTimestamp 列表编码为 JSON 字符串（用于数据库存储）
String encodeWordTimestamps(List<WordTimestamp> words) {
  return jsonEncode(words.map((w) => w.toJson()).toList());
}

/// 从 JSON 字符串解码为 WordTimestamp 列表
///
/// 解析失败返回 null（容错，避免脏数据阻塞流程）。
List<WordTimestamp>? decodeWordTimestamps(String json) {
  try {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => WordTimestamp.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return null;
  }
}
