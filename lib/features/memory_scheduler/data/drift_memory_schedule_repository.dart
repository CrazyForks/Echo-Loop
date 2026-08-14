/// 基于 Drift 的记忆调度 Repository 实现。
library;

import '../../../database/app_database.dart'
    hide MemoryReviewEvent, MemorySchedule;
import '../../../database/app_database.dart' as database show MemoryReviewEvent;
import '../../../database/daos/memory_schedule_dao.dart';
import '../application/memory_schedule_repository.dart';
import '../domain/memory_review_event.dart';
import '../domain/memory_schedule.dart';
import '../domain/memory_scheduler_commands.dart';
import '../domain/memory_scheduler_exceptions.dart';
import '../domain/memory_scheduler_results.dart';
import '../domain/memory_subject_ref.dart';
import 'memory_schedule_mapper.dart';

/// 将调度快照和评分事件在同一 Drift 事务中持久化。
final class DriftMemoryScheduleRepository implements MemoryScheduleRepository {
  /// 创建 Repository；数据库连接的生命周期仍由调用方拥有。
  DriftMemoryScheduleRepository(this._database, {MemoryScheduleMapper? mapper})
    : _mapper = mapper ?? MemoryScheduleMapper();

  final AppDatabase _database;
  final MemoryScheduleMapper _mapper;

  MemoryScheduleDao get _dao => _database.memoryScheduleDao;

  @override
  Future<MemorySchedule?> getBySubject(MemorySubjectRef subject) async {
    final row = await _dao.getBySubject(
      namespace: subject.namespace,
      subjectId: subject.subjectId,
    );
    return row == null ? null : _mapper.scheduleFromRow(row);
  }

  @override
  Future<List<MemorySchedule>> getBySubjects(
    Set<MemorySubjectRef> subjects,
  ) async {
    final rows = await _dao.getBySubjects(
      subjects.map(
        (subject) =>
            (namespace: subject.namespace, subjectId: subject.subjectId),
      ),
    );
    return rows.map(_mapper.scheduleFromRow).toList(growable: false);
  }

  @override
  Stream<MemorySchedule?> watchBySubject(MemorySubjectRef subject) {
    return _dao
        .watchBySubject(
          namespace: subject.namespace,
          subjectId: subject.subjectId,
        )
        .map((row) => row == null ? null : _mapper.scheduleFromRow(row));
  }

  @override
  Future<List<MemorySchedule>> getDue(DueMemorySchedulesQuery query) async {
    final rows = await _dao.getDue(
      namespaces: query.namespaces,
      phases: query.phases?.map((phase) => phase.name),
      dueBeforeOrAt: query.dueBeforeOrAt,
      limit: query.limit,
      afterDueAt: query.after?.dueAt,
      afterId: query.after?.id,
    );
    return rows.map(_mapper.scheduleFromRow).toList(growable: false);
  }

  @override
  Stream<int> watchDueCount(DueMemoryCountQuery query) {
    return _dao.watchDueCount(
      namespaces: query.namespaces,
      phases: query.phases?.map((phase) => phase.name),
      dueBeforeOrAt: query.dueBeforeOrAt,
    );
  }

  @override
  Future<List<MemoryReviewEvent>> getEvents(String scheduleId) async {
    final rows = await _dao.getEvents(scheduleId);
    return rows.map(_mapper.eventFromRow).toList(growable: false);
  }

  @override
  Future<MemorySchedule> createIfAbsent(MemorySchedule initial) async {
    return _database.transaction(() async {
      final existing = await getBySubject(initial.subject);
      if (existing != null) return existing;
      try {
        await _dao.insertSchedule(_mapper.scheduleToCompanion(initial));
        return initial;
      } on Exception {
        // 唯一主体约束可能由另一连接抢先满足；只在能回读到该主体时吞掉冲突。
        final raced = await getBySubject(initial.subject);
        if (raced != null) return raced;
        rethrow;
      }
    });
  }

  @override
  Future<MemoryReviewResult> commitReview(MemoryReviewCommit commit) {
    _validateReviewCommit(commit);
    return _database.transaction(() async {
      final current = await getBySubject(commit.before.subject);
      if (current == null) {
        throw const MemoryScheduleNotFoundException('评分目标不存在。');
      }
      final existing = await _dao.getEventByOperation(
        scheduleId: current.id,
        operationId: commit.event.operationId,
      );
      if (existing != null) {
        return _existingReviewResult(current, existing, commit);
      }
      if (current.status != MemoryScheduleStatus.active) {
        throw const MemoryScheduleArchivedException('归档调度不能评分。');
      }
      if (current.revision != commit.expectedRevision) {
        throw const MemoryScheduleConflictException('评分 revision 已过期。');
      }
      final lastReviewedAt = current.lastReviewedAt;
      if (lastReviewedAt != null &&
          commit.event.reviewedAt.isBefore(lastReviewedAt)) {
        throw const MemoryReviewTimeOrderException('评分时间不能早于上一次评分。');
      }
      final affected = await _dao.replaceActiveSchedule(
        id: current.id,
        expectedRevision: current.revision,
        schedule: _mapper.scheduleToCompanion(commit.after),
      );
      if (affected != 1) {
        throw const MemoryScheduleConflictException('评分 CAS 写入失败。');
      }
      final sequence = await _dao.nextEventSequence(current.id);
      final event = MemoryReviewEvent(
        id: commit.event.id,
        scheduleId: current.id,
        sequence: sequence,
        operationId: commit.event.operationId,
        rating: commit.event.rating,
        isLapse: commit.event.isLapse,
        reviewedAt: commit.event.reviewedAt,
        responseTime: commit.event.responseTime,
        profile: commit.after.profile,
        modelId: commit.after.modelId,
        modelStateVersion: commit.after.modelStateVersion,
        dueBefore: commit.event.dueBefore,
        dueAfter: commit.after.dueAt,
        scheduleRevisionAfter: commit.after.revision,
        createdAt: commit.event.createdAt,
      );
      await _dao.insertEvent(_mapper.eventToCompanion(event));
      return MemoryReviewResult(
        schedule: commit.after,
        event: event,
        wasIdempotentReplay: false,
      );
    });
  }

  @override
  Future<MemorySchedule> replaceLifecycle(
    MemorySchedule before,
    MemorySchedule after,
  ) async {
    if (before.status == after.status) {
      throw const MemoryScheduleStatusException('生命周期操作必须改变 status。');
    }
    _validateReplacement(before, after);
    return _database.transaction(() async {
      final affected = await _dao.replaceByStatus(
        id: before.id,
        expectedRevision: before.revision,
        expectedStatus: before.status.name,
        schedule: _mapper.scheduleToCompanion(after),
      );
      if (affected != 1) {
        throw const MemoryScheduleConflictException('生命周期 CAS 写入失败。');
      }
      return after;
    });
  }

  @override
  Future<void> purge(MemorySchedule schedule) async {
    await _database.transaction(() async {
      final affected = await _dao.deleteByRevision(
        id: schedule.id,
        expectedRevision: schedule.revision,
      );
      if (affected != 1) {
        throw const MemoryScheduleConflictException('永久清除 revision 已过期。');
      }
    });
  }

  MemoryReviewResult _existingReviewResult(
    MemorySchedule current,
    database.MemoryReviewEvent rawEvent,
    MemoryReviewCommit commit,
  ) {
    final event = _mapper.eventFromRow(rawEvent);
    final samePayload =
        event.rating == commit.event.rating &&
        event.reviewedAt == commit.event.reviewedAt.toUtc() &&
        event.responseTime == commit.event.responseTime;
    if (!samePayload) {
      throw const MemoryOperationIdConflictException('operationId 被不同评分重复使用。');
    }
    if (current.revision != event.scheduleRevisionAfter) {
      throw const MemoryIdempotencyReplayStaleException(
        'operationId 已不是当前快照对应的最后事件。',
      );
    }
    return MemoryReviewResult(
      schedule: current,
      event: event,
      wasIdempotentReplay: true,
    );
  }

  void _validateReviewCommit(MemoryReviewCommit commit) {
    if (commit.before.id != commit.after.id ||
        commit.before.subject != commit.after.subject ||
        commit.after.revision != commit.before.revision + 1 ||
        commit.after.status != MemoryScheduleStatus.active) {
      throw const MemoryScheduleConflictException('评分提交的快照前后关系无效。');
    }
  }

  void _validateReplacement(MemorySchedule before, MemorySchedule after) {
    if (before.id != after.id ||
        before.subject != after.subject ||
        after.revision != before.revision + 1) {
      throw const MemoryScheduleConflictException('替换快照必须保持主体并递增 revision。');
    }
  }
}
