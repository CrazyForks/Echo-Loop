import 'package:drift/drift.dart';

/// 通用每日复习入队记录。
///
/// 只记录某个业务命名空间下的主体是否已纳入某个本地日的新卡预算，不参与
/// FSRS 评分审计。`namespace` 区分收藏句（`favorite_sentence`）、收藏单词
/// （`saved_word`）、收藏意群（`saved_phrase`）等不同调度队列，避免不同内容
/// 类型的每日新卡上限互相污染或需要各自建表。
class MemoryReviewQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get namespace => text()();
  TextColumn get subjectId => text()();
  TextColumn get localDate => text()();
  DateTimeColumn get enqueuedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {namespace, subjectId, localDate},
  ];
}
