import 'package:drift/drift.dart';

/// 跨业务内容的记忆调度当前快照。
class MemorySchedules extends Table {
  TextColumn get id => text()();
  TextColumn get namespace => text()();
  TextColumn get subjectId => text()();
  TextColumn get profileId => text()();
  IntColumn get profileVersion => integer()();
  TextColumn get modelId => text()();
  IntColumn get modelStateVersion => integer()();
  TextColumn get modelStateJson => text().withDefault(const Constant('{}'))();
  TextColumn get phase => text()();
  TextColumn get status => text()();
  DateTimeColumn get dueAt => dateTime()();
  DateTimeColumn get lastReviewedAt => dateTime().nullable()();
  IntColumn get reviewCount => integer().withDefault(const Constant(0))();
  IntColumn get lapseCount => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {namespace, subjectId},
  ];

  @override
  List<String> get customConstraints => const <String>[
    "CHECK (length(trim(id)) > 0)",
    "CHECK (length(trim(namespace)) > 0)",
    "CHECK (length(trim(subject_id)) > 0)",
    "CHECK (length(trim(profile_id)) > 0)",
    "CHECK (length(trim(model_id)) > 0)",
    'CHECK (profile_version > 0)',
    'CHECK (model_state_version > 0)',
    "CHECK (phase IN ('newItem', 'learning', 'review', 'relearning'))",
    "CHECK (status IN ('active', 'archived'))",
    "CHECK ((status = 'active' AND archived_at IS NULL) OR (status = 'archived' AND archived_at IS NOT NULL))",
    'CHECK (review_count >= 0)',
    'CHECK (lapse_count >= 0)',
    'CHECK (revision >= 0)',
  ];
}
