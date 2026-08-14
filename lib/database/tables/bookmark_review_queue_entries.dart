import 'package:drift/drift.dart';

/// 收藏句每日复习入队记录。
///
/// 只记录业务队列是否已纳入某个本地日，不参与 FSRS 评分审计。
class BookmarkReviewQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get subjectId => text()();
  TextColumn get localDate => text()();
  DateTimeColumn get enqueuedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {subjectId, localDate},
  ];
}
