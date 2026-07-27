/// 记忆调度快照与审计事件的持久化端口。
library;

import '../domain/memory_review_event.dart';
import '../domain/memory_rating.dart';
import '../domain/memory_schedule.dart';
import '../domain/memory_scheduler_commands.dart';
import '../domain/memory_scheduler_results.dart';
import '../domain/memory_subject_ref.dart';

/// 一次评分事务所需的、尚未分配 sequence 的审计事件事实。
final class MemoryReviewEventDraft {
  /// 创建评分事件草稿。
  MemoryReviewEventDraft({
    required String id,
    required String operationId,
    required this.rating,
    required this.isLapse,
    required DateTime reviewedAt,
    required this.responseTime,
    required DateTime dueBefore,
    required DateTime createdAt,
  }) : id = memoryRequiredText(id, 'event.id'),
       operationId = memoryRequiredText(operationId, 'event.operationId'),
       reviewedAt = reviewedAt.toUtc(),
       dueBefore = dueBefore.toUtc(),
       createdAt = createdAt.toUtc();

  final String id;
  final String operationId;
  final MemoryRating rating;
  final bool isLapse;
  final DateTime reviewedAt;
  final Duration? responseTime;
  final DateTime dueBefore;
  final DateTime createdAt;
}

/// 已由 application 层完成算法计算的原子评分写入请求。
final class MemoryReviewCommit {
  /// 创建评分提交请求。
  const MemoryReviewCommit({
    required this.before,
    required this.after,
    required this.event,
    required this.expectedRevision,
  });

  final MemorySchedule before;
  final MemorySchedule after;
  final MemoryReviewEventDraft event;
  final int expectedRevision;
}

/// 屏蔽 Drift 的调度持久化端口。
abstract interface class MemoryScheduleRepository {
  /// 按主体读取当前快照。
  Future<MemorySchedule?> getBySubject(MemorySubjectRef subject);

  /// 批量读取已有快照。
  Future<List<MemorySchedule>> getBySubjects(Set<MemorySubjectRef> subjects);

  /// 监听一个主体的当前快照。
  Stream<MemorySchedule?> watchBySubject(MemorySubjectRef subject);

  /// 查询活动且已到期的快照。
  Future<List<MemorySchedule>> getDue(DueMemorySchedulesQuery query);

  /// 监听活动且已到期的数量。
  Stream<int> watchDueCount(DueMemoryCountQuery query);

  /// 读取完整评分审计历史。
  Future<List<MemoryReviewEvent>> getEvents(String scheduleId);

  /// 幂等创建初始快照；已有项不改变其固定 Profile。
  Future<MemorySchedule> createIfAbsent(MemorySchedule initial);

  /// 以 revision CAS 提交当前快照和只追加评分事件。
  Future<MemoryReviewResult> commitReview(MemoryReviewCommit commit);

  /// 以 revision CAS 替换历史重放后的快照。
  Future<MemorySchedule> replaceAfterReplay(
    MemorySchedule before,
    MemorySchedule after,
  );

  /// 以 revision CAS 更新归档或恢复后的快照。
  Future<MemorySchedule> replaceLifecycle(
    MemorySchedule before,
    MemorySchedule after,
  );

  /// 以 revision CAS 永久清除快照及其审计事件。
  Future<void> purge(MemorySchedule schedule);
}
