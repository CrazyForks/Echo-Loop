/// 记忆调度应用服务的输出模型。
library;

import 'memory_rating.dart';
import 'memory_review_event.dart';
import 'memory_model_adapter.dart';
import 'memory_schedule.dart';

/// 一种评分对应的下一次调度预览。
final class MemoryRatingPreview {
  /// 创建评分预览。
  MemoryRatingPreview({
    required this.scheduleId,
    required this.revision,
    required this.rating,
    required DateTime reviewedAt,
    required DateTime dueAt,
    required this.interval,
    required this.phase,
    required this.transition,
  }) : reviewedAt = reviewedAt.toUtc(),
       dueAt = dueAt.toUtc();

  final String scheduleId;
  final int revision;
  final MemoryRating rating;
  final DateTime reviewedAt;
  final DateTime dueAt;
  final Duration interval;
  final MemorySchedulePhase phase;

  /// 生成本次预览的完整模型状态转换，提交时直接复用以保持随机结果一致。
  final MemoryModelTransition transition;
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
