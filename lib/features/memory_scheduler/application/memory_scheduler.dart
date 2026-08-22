/// 面向业务功能的通用记忆调度应用服务接口。
library;

import '../domain/memory_schedule.dart';
import '../domain/memory_scheduler_commands.dart';
import '../domain/memory_scheduler_results.dart';
import '../domain/memory_subject_ref.dart';

/// 为调度快照和审计事件生成稳定 ID 的端口。
abstract interface class MemoryIdGenerator {
  /// 返回一个新的全局唯一 ID。
  String newId();
}

/// 上层业务使用的模型无关记忆调度 facade。
abstract interface class MemoryScheduler {
  /// 幂等确保业务主体拥有一个调度快照。
  Future<MemorySchedule> ensureSchedule(EnsureMemoryScheduleCommand command);

  /// 读取一个业务主体的调度快照。
  Future<MemorySchedule?> getSchedule(MemorySubjectRef subject);

  /// 批量读取已有调度快照。
  Future<List<MemorySchedule>> getSchedules(Set<MemorySubjectRef> subjects);

  /// 监听一个业务主体的调度快照。
  Stream<MemorySchedule?> watchSchedule(MemorySubjectRef subject);

  /// 查询到期调度。
  Future<List<MemorySchedule>> getDueSchedules(DueMemorySchedulesQuery query);

  /// 读取到期调度数量。
  Future<int> getDueCount(DueMemoryCountQuery query);

  /// 监听到期调度数量。
  Stream<int> watchDueCount(DueMemoryCountQuery query);

  /// 计算一个调度快照在给定时间的算法可回忆率。
  double retrievability(MemorySchedule schedule, DateTime at);

  /// 无副作用地预览四种评分结果。
  Future<MemoryRatingPreviewSet> previewRatings(
    PreviewMemoryRatingsQuery query,
  );

  /// 提交一次带幂等键的用户评分。
  Future<MemoryReviewResult> review(ReviewMemoryCommand command);

  /// 归档调度快照。
  Future<MemorySchedule> archive(ArchiveMemoryScheduleCommand command);

  /// 恢复归档调度快照。
  Future<MemorySchedule> restore(RestoreMemoryScheduleCommand command);

  /// 永久清除快照及审计历史。
  Future<void> purge(PurgeMemoryScheduleCommand command);
}
