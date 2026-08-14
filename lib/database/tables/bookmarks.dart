import 'package:drift/drift.dart';

import 'audio_items.dart';

/// 书签表（增强版）
/// 存储完整句子信息，防止字幕重新解析后索引错位
class Bookmarks extends Table {
  /// 自增主键
  IntColumn get id => integer().autoIncrement()();

  /// 跨数据库迁移和字幕重解析仍保持稳定的记忆主体 ID。
  TextColumn get memorySubjectId => text().nullable()();

  /// 音频 ID，外键关联 audio_items.id
  TextColumn get audioItemId =>
      text().references(AudioItems, #id, onDelete: KeyAction.cascade)();

  /// 句子索引（快速查询 + 向后兼容）
  IntColumn get sentenceIndex => integer()();

  /// 句子文本（防止索引错位时可通过文本匹配）
  TextColumn get sentenceText => text()();

  /// 句子起始时间（秒）
  RealColumn get startTime => real()();

  /// 句子结束时间（秒）
  RealColumn get endTime => real()();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime()();

  /// 最后修改时间
  DateTimeColumn get updatedAt => dateTime()();

  /// 软删除标记
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// 同步状态
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {audioItemId, sentenceIndex},
  ];
}
