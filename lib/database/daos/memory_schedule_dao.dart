import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/memory_review_events.dart';
import '../tables/memory_schedules.dart';

part 'memory_schedule_dao.g.dart';

/// 记忆调度表的低层访问入口。
@DriftAccessor(tables: [MemorySchedules, MemoryReviewEvents])
class MemoryScheduleDao extends DatabaseAccessor<AppDatabase>
    with _$MemoryScheduleDaoMixin {
  /// 创建记忆调度 DAO。
  MemoryScheduleDao(super.db);

  /// 按业务主体读取当前快照。
  Future<MemorySchedule?> getBySubject({
    required String namespace,
    required String subjectId,
  }) {
    return (select(memorySchedules)
          ..where(
            (table) =>
                table.namespace.equals(namespace) &
                table.subjectId.equals(subjectId),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// 监听一个业务主体的当前快照。
  Stream<MemorySchedule?> watchBySubject({
    required String namespace,
    required String subjectId,
  }) {
    return (select(memorySchedules)
          ..where(
            (table) =>
                table.namespace.equals(namespace) &
                table.subjectId.equals(subjectId),
          )
          ..limit(1))
        .watchSingleOrNull();
  }

  /// 按主体集合读取快照；调用方负责还原输入顺序。
  Future<List<MemorySchedule>> getBySubjects(
    Iterable<({String namespace, String subjectId})> subjects,
  ) async {
    final result = <MemorySchedule>[];
    for (final subject in subjects) {
      final row = await getBySubject(
        namespace: subject.namespace,
        subjectId: subject.subjectId,
      );
      if (row != null) result.add(row);
    }
    return result;
  }

  /// 读取活动且到期的快照，按稳定 keyset 顺序排序。
  Future<List<MemorySchedule>> getDue({
    required Iterable<String> namespaces,
    required Iterable<String>? phases,
    required DateTime dueBeforeOrAt,
    required int limit,
    required DateTime? afterDueAt,
    required String? afterId,
  }) {
    final namespaceValues = namespaces.toList(growable: false);
    final phaseValues = phases?.toList(growable: false);
    final query = select(memorySchedules)
      ..where(
        (table) =>
            table.status.equals('active') &
            table.namespace.isIn(namespaceValues) &
            table.dueAt.isSmallerOrEqualValue(dueBeforeOrAt) &
            (phaseValues == null
                ? const Constant(true)
                : table.phase.isIn(phaseValues)),
      )
      ..orderBy([
        (table) => OrderingTerm.asc(table.dueAt),
        (table) => OrderingTerm.asc(table.id),
      ])
      ..limit(limit);
    final cursorDueAt = afterDueAt;
    final cursorId = afterId;
    if (cursorDueAt != null && cursorId != null) {
      query.where(
        (table) =>
            table.dueAt.isBiggerThanValue(cursorDueAt) |
            (table.dueAt.equals(cursorDueAt) &
                table.id.isBiggerThanValue(cursorId)),
      );
    }
    return query.get();
  }

  /// 监听活动且到期的调度数量。
  Stream<int> watchDueCount({
    required Iterable<String> namespaces,
    required Iterable<String>? phases,
    required DateTime dueBeforeOrAt,
  }) {
    final namespaceValues = namespaces.toList(growable: false);
    final phaseValues = phases?.toList(growable: false);
    final count = memorySchedules.id.count();
    final query = selectOnly(memorySchedules)
      ..addColumns([count])
      ..where(
        memorySchedules.status.equals('active') &
            memorySchedules.namespace.isIn(namespaceValues) &
            memorySchedules.dueAt.isSmallerOrEqualValue(dueBeforeOrAt) &
            (phaseValues == null
                ? const Constant(true)
                : memorySchedules.phase.isIn(phaseValues)),
      );
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  /// 按顺序读取一个调度的全部审计事件。
  Future<List<MemoryReviewEvent>> getEvents(String scheduleId) {
    return (select(memoryReviewEvents)
          ..where((table) => table.scheduleId.equals(scheduleId))
          ..orderBy([(table) => OrderingTerm.asc(table.sequence)]))
        .get();
  }

  /// 在事务内按幂等键读取已有事件。
  Future<MemoryReviewEvent?> getEventByOperation({
    required String scheduleId,
    required String operationId,
  }) {
    return (select(memoryReviewEvents)
          ..where(
            (table) =>
                table.scheduleId.equals(scheduleId) &
                table.operationId.equals(operationId),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// 插入一个初始快照；唯一主体冲突由调用方处理。
  Future<void> insertSchedule(MemorySchedulesCompanion schedule) async {
    await into(memorySchedules).insert(schedule);
  }

  /// 以 revision 和状态为条件替换快照，返回受影响行数。
  Future<int> replaceActiveSchedule({
    required String id,
    required int expectedRevision,
    required MemorySchedulesCompanion schedule,
  }) {
    return (update(memorySchedules)..where(
          (table) =>
              table.id.equals(id) &
              table.revision.equals(expectedRevision) &
              table.status.equals('active'),
        ))
        .write(schedule);
  }

  /// 插入评分事件；调用方在同一事务内已确定 sequence。
  Future<void> insertEvent(MemoryReviewEventsCompanion event) async {
    await into(memoryReviewEvents).insert(event);
  }

  /// 在同一事务内分配下一个审计事件序号。
  Future<int> nextEventSequence(String scheduleId) async {
    final maximum = memoryReviewEvents.sequence.max();
    final query = selectOnly(memoryReviewEvents)
      ..addColumns([maximum])
      ..where(memoryReviewEvents.scheduleId.equals(scheduleId));
    final row = await query.getSingle();
    return (row.read(maximum) ?? 0) + 1;
  }

  /// 以 revision 和当前状态为条件变更生命周期快照。
  Future<int> replaceByStatus({
    required String id,
    required int expectedRevision,
    required String expectedStatus,
    required MemorySchedulesCompanion schedule,
  }) {
    return (update(memorySchedules)..where(
          (table) =>
              table.id.equals(id) &
              table.revision.equals(expectedRevision) &
              table.status.equals(expectedStatus),
        ))
        .write(schedule);
  }

  /// 以 revision 删除快照，关联事件由 FK cascade 清除。
  Future<int> deleteByRevision({
    required String id,
    required int expectedRevision,
  }) {
    return (delete(memorySchedules)..where(
          (table) =>
              table.id.equals(id) & table.revision.equals(expectedRevision),
        ))
        .go();
  }
}
