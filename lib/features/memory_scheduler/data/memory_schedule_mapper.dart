/// Drift 行与记忆调度领域模型之间的严格映射。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../../database/app_database.dart' as database;
import '../domain/memory_profile.dart';
import '../domain/memory_rating.dart';
import '../domain/memory_review_event.dart' as domain;
import '../domain/memory_schedule.dart' as domain;
import '../domain/memory_scheduler_exceptions.dart';
import '../domain/memory_subject_ref.dart';

/// 将持久化行转换为领域模型，并拒绝损坏的枚举或 JSON。
final class MemoryScheduleMapper {
  /// 从 Drift 快照行构造领域快照。
  domain.MemorySchedule scheduleFromRow(database.MemorySchedule row) {
    return domain.MemorySchedule(
      id: row.id,
      subject: MemorySubjectRef(
        namespace: row.namespace,
        subjectId: row.subjectId,
      ),
      profile: MemoryProfileRef(
        profileId: row.profileId,
        profileVersion: row.profileVersion,
      ),
      modelId: row.modelId,
      modelStateVersion: row.modelStateVersion,
      phase: _phase(row.phase),
      status: _status(row.status),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastReviewedAt: row.lastReviewedAt,
      dueAt: row.dueAt,
      reviewCount: row.reviewCount,
      lapseCount: row.lapseCount,
      revision: row.revision,
      modelState: _jsonMap(row.modelStateJson),
      archivedAt: row.archivedAt,
    );
  }

  /// 从 Drift 事件行构造领域审计事件。
  domain.MemoryReviewEvent eventFromRow(database.MemoryReviewEvent row) {
    final responseTimeMs = row.responseTimeMs;
    return domain.MemoryReviewEvent(
      id: row.id,
      scheduleId: row.scheduleId,
      sequence: row.sequence,
      operationId: row.operationId,
      rating: _rating(row.rating),
      isLapse: row.isLapse,
      reviewedAt: row.reviewedAt,
      responseTime: responseTimeMs == null
          ? null
          : Duration(milliseconds: responseTimeMs),
      profile: MemoryProfileRef(
        profileId: row.profileId,
        profileVersion: row.profileVersion,
      ),
      modelId: row.modelId,
      modelStateVersion: row.modelStateVersion,
      dueBefore: row.dueBefore,
      dueAfter: row.dueAfter,
      scheduleRevisionAfter: row.scheduleRevisionAfter,
      createdAt: row.createdAt,
    );
  }

  /// 将领域快照编码为 Drift companion。
  database.MemorySchedulesCompanion scheduleToCompanion(
    domain.MemorySchedule schedule,
  ) {
    return database.MemorySchedulesCompanion.insert(
      id: schedule.id,
      namespace: schedule.subject.namespace,
      subjectId: schedule.subject.subjectId,
      profileId: schedule.profile.profileId,
      profileVersion: schedule.profile.profileVersion,
      modelId: schedule.modelId,
      modelStateVersion: schedule.modelStateVersion,
      modelStateJson: Value(jsonEncode(schedule.modelState)),
      phase: schedule.phase.name,
      status: schedule.status.name,
      dueAt: schedule.dueAt.toUtc(),
      lastReviewedAt: Value(schedule.lastReviewedAt?.toUtc()),
      reviewCount: Value(schedule.reviewCount),
      lapseCount: Value(schedule.lapseCount),
      revision: Value(schedule.revision),
      createdAt: schedule.createdAt.toUtc(),
      updatedAt: schedule.updatedAt.toUtc(),
      archivedAt: Value(schedule.archivedAt?.toUtc()),
    );
  }

  /// 将领域事件编码为 Drift companion。
  database.MemoryReviewEventsCompanion eventToCompanion(
    domain.MemoryReviewEvent event,
  ) {
    return database.MemoryReviewEventsCompanion.insert(
      id: event.id,
      scheduleId: event.scheduleId,
      sequence: event.sequence,
      operationId: event.operationId,
      rating: event.rating.name,
      isLapse: event.isLapse,
      reviewedAt: event.reviewedAt.toUtc(),
      responseTimeMs: Value(event.responseTime?.inMilliseconds),
      profileId: event.profile.profileId,
      profileVersion: event.profile.profileVersion,
      modelId: event.modelId,
      modelStateVersion: event.modelStateVersion,
      dueBefore: event.dueBefore.toUtc(),
      dueAfter: event.dueAfter.toUtc(),
      scheduleRevisionAfter: event.scheduleRevisionAfter,
      createdAt: event.createdAt.toUtc(),
    );
  }
}

Map<String, Object?> _jsonMap(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('根节点不是对象。');
    }
    final result = <String, Object?>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('对象键不是字符串。');
      }
      result[key] = entry.value;
    }
    return result;
  } on FormatException catch (error) {
    throw MemoryModelStateCorruptedException('modelStateJson 无法解码: $error');
  }
}

domain.MemorySchedulePhase _phase(String value) => switch (value) {
  'newItem' => domain.MemorySchedulePhase.newItem,
  'learning' => domain.MemorySchedulePhase.learning,
  'review' => domain.MemorySchedulePhase.review,
  'relearning' => domain.MemorySchedulePhase.relearning,
  _ => throw MemoryModelStateCorruptedException('未知调度 phase: $value'),
};

domain.MemoryScheduleStatus _status(String value) => switch (value) {
  'active' => domain.MemoryScheduleStatus.active,
  'archived' => domain.MemoryScheduleStatus.archived,
  _ => throw MemoryModelStateCorruptedException('未知调度 status: $value'),
};

MemoryRating _rating(String value) => switch (value) {
  'again' => MemoryRating.again,
  'hard' => MemoryRating.hard,
  'good' => MemoryRating.good,
  'easy' => MemoryRating.easy,
  _ => throw MemoryModelStateCorruptedException('未知评分: $value'),
};
