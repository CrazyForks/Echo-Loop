/// 词典条目模型
///
/// 对应 dict.sqlite 中 words 表的一行记录，包含音标、释义、柯林斯星级和考试标签。
library;

/// 词典查询结果
class DictEntry {
  /// 单词原文
  final String word;

  /// 音标（IPA 格式）
  final String phonetic;

  /// 中文释义（可能包含词性前缀，多义项用换行分隔）
  final String? translation;

  /// 柯林斯星级（0 表示无星级，1-5 表示星级）
  final int collins;

  /// 考试标签列表（如 CET4、CET6、TOEFL 等）
  final List<String> examTags;

  const DictEntry({
    required this.word,
    required this.phonetic,
    this.translation,
    this.collins = 0,
    this.examTags = const [],
  });

  /// 需要显示的考试标签（仅保留 cet4/cet6/toefl/ielts/gre）
  static const _displayableTags = {'cet4', 'cet6', 'toefl', 'ielts', 'gre'};

  /// 从数据库行构建
  factory DictEntry.fromRow({
    required String word,
    required String phonetic,
    String? translation,
    int collins = 0,
    String? tag,
  }) {
    // 解析空格分隔的标签，只保留可显示的标签
    final examTags = <String>[];
    if (tag != null && tag.isNotEmpty) {
      for (final t in tag.split(' ')) {
        if (_displayableTags.contains(t)) {
          examTags.add(t.toUpperCase());
        }
      }
    }

    return DictEntry(
      word: word,
      phonetic: phonetic,
      translation: translation,
      collins: collins,
      examTags: examTags,
    );
  }
}
