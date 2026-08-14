/// 记忆调度应用服务的输入命令。
library;

import 'memory_rating.dart';
import 'memory_profile.dart';
import 'memory_schedule.dart';
import 'memory_scheduler_results.dart';
import 'memory_subject_ref.dart';

/// 请求确保某个业务主体拥有调度。
final class EnsureMemoryScheduleCommand {
  /// 创建确保调度命令。
  EnsureMemoryScheduleCommand({
    required this.subject,
    required this.profile,
    required DateTime occurredAt,
  }) : occurredAt = occurredAt.toUtc();

  final MemorySubjectRef subject;
  final MemoryProfileRef? profile;
  final DateTime occurredAt;
}

/// 到期列表的类型化 keyset 游标。
final class MemoryDueCursor {
  /// 创建到期游标。
  MemoryDueCursor({required DateTime dueAt, required String id})
    : dueAt = dueAt.toUtc(),
      id = memoryRequiredText(id, 'id');

  final DateTime dueAt;
  final String id;
}

/// 查询到期调度的条件。
final class DueMemorySchedulesQuery {
  /// 创建到期列表查询。
  DueMemorySchedulesQuery({
    required Set<String> namespaces,
    required Set<MemorySchedulePhase>? phases,
    required DateTime dueBeforeOrAt,
    required this.limit,
    required this.after,
  }) : namespaces = _namespaces(namespaces),
       phases = phases == null ? null : Set.unmodifiable(phases),
       dueBeforeOrAt = dueBeforeOrAt.toUtc() {
    if (phases != null && phases.isEmpty) {
      throw ArgumentError.value(phases, 'phases', '非 null 时不能为空。');
    }
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', '必须在 1 到 500 之间。');
    }
  }

  final Set<String> namespaces;
  final Set<MemorySchedulePhase>? phases;
  final DateTime dueBeforeOrAt;
  final int limit;
  final MemoryDueCursor? after;
}

/// 查询到期数量的条件。
final class DueMemoryCountQuery {
  /// 创建到期数量查询。
  DueMemoryCountQuery({
    required Set<String> namespaces,
    required Set<MemorySchedulePhase>? phases,
    required DateTime dueBeforeOrAt,
  }) : namespaces = _namespaces(namespaces),
       phases = phases == null ? null : Set.unmodifiable(phases),
       dueBeforeOrAt = dueBeforeOrAt.toUtc() {
    if (phases != null && phases.isEmpty) {
      throw ArgumentError.value(phases, 'phases', '非 null 时不能为空。');
    }
  }

  final Set<String> namespaces;
  final Set<MemorySchedulePhase>? phases;
  final DateTime dueBeforeOrAt;
}

/// 请求只读预览四种评分结果。
final class PreviewMemoryRatingsQuery {
  /// 创建评分预览查询。
  PreviewMemoryRatingsQuery({
    required this.subject,
    required DateTime reviewedAt,
    required this.expectedRevision,
  }) : reviewedAt = reviewedAt.toUtc();

  final MemorySubjectRef subject;
  final DateTime reviewedAt;
  final int? expectedRevision;
}

/// 请求提交一次用户评分。
final class ReviewMemoryCommand {
  /// 创建评分提交命令。
  ReviewMemoryCommand({
    required this.subject,
    required this.rating,
    required DateTime reviewedAt,
    this.preview,
    required this.responseTime,
    required String operationId,
    required this.expectedRevision,
  }) : reviewedAt = reviewedAt.toUtc(),
       operationId = memoryRequiredText(operationId, 'operationId') {
    if (expectedRevision < 0) {
      throw ArgumentError.value(expectedRevision, 'expectedRevision', '不得为负。');
    }
    if (responseTime != null &&
        (responseTime! < Duration.zero ||
            responseTime! > const Duration(hours: 24))) {
      throw ArgumentError.value(
        responseTime,
        'responseTime',
        '必须在 0 到 24 小时之间。',
      );
    }
  }

  final MemorySubjectRef subject;
  final MemoryRating rating;

  /// 用户看到并选择的评分预览；UI 提交时必须传入以复用随机结果。
  final MemoryRatingPreview? preview;
  final DateTime reviewedAt;
  final Duration? responseTime;
  final String operationId;
  final int expectedRevision;
}

/// 归档调度的命令。
final class ArchiveMemoryScheduleCommand {
  /// 创建归档命令。
  ArchiveMemoryScheduleCommand({
    required this.subject,
    required DateTime archivedAt,
    required this.expectedRevision,
  }) : archivedAt = archivedAt.toUtc() {
    _revision(expectedRevision);
  }

  final MemorySubjectRef subject;
  final DateTime archivedAt;
  final int expectedRevision;
}

/// 恢复调度的命令。
final class RestoreMemoryScheduleCommand {
  /// 创建恢复命令。
  RestoreMemoryScheduleCommand({
    required this.subject,
    required DateTime restoredAt,
    required this.expectedRevision,
  }) : restoredAt = restoredAt.toUtc() {
    _revision(expectedRevision);
  }

  final MemorySubjectRef subject;
  final DateTime restoredAt;
  final int expectedRevision;
}

/// 永久删除调度的命令。
final class PurgeMemoryScheduleCommand {
  /// 创建永久删除命令。
  PurgeMemoryScheduleCommand({
    required this.subject,
    required this.expectedRevision,
  }) {
    _revision(expectedRevision);
  }

  final MemorySubjectRef subject;
  final int expectedRevision;
}

Set<String> _namespaces(Set<String> values) {
  final normalized = values
      .map((value) => memoryRequiredText(value, 'namespaces'))
      .toSet();
  if (normalized.isEmpty) {
    throw ArgumentError.value(values, 'namespaces', '不能为空。');
  }
  return Set.unmodifiable(normalized);
}

void _revision(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'expectedRevision', '不得为负。');
  }
}
