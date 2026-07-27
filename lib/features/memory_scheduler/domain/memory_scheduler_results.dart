/// 记忆调度应用服务的输出模型。
library;

import 'memory_profile.dart';
import 'memory_rating.dart';
import 'memory_review_event.dart';
import 'memory_schedule.dart';

/// 一种评分对应的下一次调度预览。
final class MemoryRatingPreview {
  /// 创建评分预览。
  MemoryRatingPreview({
    required this.rating,
    required DateTime dueAt,
    required this.interval,
    required this.phase,
  }) : dueAt = dueAt.toUtc();

  final MemoryRating rating;
  final DateTime dueAt;
  final Duration interval;
  final MemorySchedulePhase phase;
}

/// 四种评分的完整预览，避免上层自行处理不完整 Map。
final class MemoryRatingPreviewSet {
  /// 创建四种评分预览。
  const MemoryRatingPreviewSet({
    required this.scheduleId,
    required this.revision,
    required this.reviewedAt,
    required this.again,
    required this.hard,
    required this.good,
    required this.easy,
  });

  final String scheduleId;
  final int revision;
  final DateTime reviewedAt;
  final MemoryRatingPreview again;
  final MemoryRatingPreview hard;
  final MemoryRatingPreview good;
  final MemoryRatingPreview easy;
}

/// 一次评分提交后的调度与审计事件。
final class MemoryReviewResult {
  /// 创建评分结果。
  const MemoryReviewResult({
    required this.schedule,
    required this.event,
    required this.wasIdempotentReplay,
  });

  final MemorySchedule schedule;
  final MemoryReviewEvent event;
  final bool wasIdempotentReplay;
}

/// 一次 Profile 重放迁移的结果。
final class MemoryProfileMigrationResult {
  /// 创建迁移结果。
  const MemoryProfileMigrationResult({
    required this.schedule,
    required this.previousProfile,
    required this.replayedEventCount,
  });

  final MemorySchedule schedule;
  final MemoryProfileRef previousProfile;
  final int replayedEventCount;
}
