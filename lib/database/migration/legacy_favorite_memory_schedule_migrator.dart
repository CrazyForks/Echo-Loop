/// 旧收藏到通用记忆调度快照的启动期兼容迁移。
library;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/memory_scheduler/config/memory_profiles.dart';
import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/domain/memory_namespaces.dart';
import '../../features/memory_scheduler/domain/memory_schedule.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../services/app_logger.dart';
import '../app_database.dart';

/// 旧收藏迁移的可观测统计，供启动日志和回归测试使用。
final class LegacyFavoriteMemoryScheduleMigrationReport {
  int scanned = 0;
  int subjectIdsBackfilled = 0;
  int activeSchedulesCreated = 0;
  int archivedSchedulesCreated = 0;
  int schedulesRestored = 0;
  int schedulesArchived = 0;
  int orphanSchedulesArchived = 0;
  int unavailableAudioBookmarksArchived = 0;
  int invalidSentencesSkipped = 0;
  int failures = 0;
}

/// 为旧收藏补齐 FSRS 快照，并收敛收藏与快照的生命周期状态。
///
/// 本迁移没有完成标记：每次启动均可安全重跑，以便前一次启动中断后继续补齐。
final class LegacyFavoriteMemoryScheduleMigrator {
  /// 创建旧收藏调度迁移器。
  LegacyFavoriteMemoryScheduleMigrator({
    required AppDatabase database,
    required MemoryScheduler scheduler,
    Clock? clock,
    Uuid? uuid,
  }) : _database = database,
       _scheduler = scheduler,
       _clock = clock ?? const Clock(),
       _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final MemoryScheduler _scheduler;
  final Clock _clock;
  final Uuid _uuid;

  /// 执行一次幂等迁移；单项失败不阻止其余旧收藏在本次启动中被修复。
  Future<LegacyFavoriteMemoryScheduleMigrationReport> migrate() async {
    final report = LegacyFavoriteMemoryScheduleMigrationReport();
    final migratedAt = _clock.now().toUtc();
    final audioItems = await _database.select(_database.audioItems).get();
    final activeAudioItemIds = audioItems
        .where((audio) => audio.deletedAt == null)
        .map((audio) => audio.id)
        .toSet();
    final subjectsByNamespace = <String, Set<String>>{
      kSavedSentenceNamespace: <String>{},
      kSavedWordOrPhraseNamespace: <String>{},
      kSavedSenseGroupNamespace: <String>{},
    };

    for (final bookmark in await _database.select(_database.bookmarks).get()) {
      report.scanned += 1;
      final subjectId = await _migrateBookmark(
        bookmark,
        activeAudioItemIds,
        migratedAt,
        report,
      );
      if (subjectId != null) {
        subjectsByNamespace[kSavedSentenceNamespace]!.add(subjectId);
      }
    }
    for (final word in await _database.select(_database.savedWords).get()) {
      report.scanned += 1;
      final subjectId = await _migrateWord(word, migratedAt, report);
      if (subjectId != null) {
        subjectsByNamespace[kSavedWordOrPhraseNamespace]!.add(subjectId);
      }
    }
    for (final group
        in await _database.select(_database.savedSenseGroups).get()) {
      report.scanned += 1;
      final subjectId = await _migrateSenseGroup(group, migratedAt, report);
      if (subjectId != null) {
        subjectsByNamespace[kSavedSenseGroupNamespace]!.add(subjectId);
      }
    }
    await _archiveOrphanActiveSchedules(
      subjectsByNamespace,
      migratedAt,
      report,
    );

    AppLogger.log(
      'LegacyFavoriteMemoryScheduleMigration',
      'completed scanned=${report.scanned} subjectIdsBackfilled=${report.subjectIdsBackfilled} '
          'activeSchedulesCreated=${report.activeSchedulesCreated} '
          'archivedSchedulesCreated=${report.archivedSchedulesCreated} '
          'schedulesRestored=${report.schedulesRestored} schedulesArchived=${report.schedulesArchived} '
          'orphanSchedulesArchived=${report.orphanSchedulesArchived} '
          'unavailableAudioBookmarksArchived=${report.unavailableAudioBookmarksArchived} '
          'invalidSentencesSkipped=${report.invalidSentencesSkipped} failures=${report.failures}',
    );
    return report;
  }

  Future<String?> _migrateBookmark(
    Bookmark bookmark,
    Set<String> activeAudioItemIds,
    DateTime migratedAt,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) async {
    try {
      final subjectId = await _bookmarkSubjectId(bookmark, report);
      final isReviewable =
          bookmark.sentenceText.trim().isNotEmpty &&
          bookmark.endTime > bookmark.startTime;
      if (!isReviewable && bookmark.deletedAt == null) {
        report.invalidSentencesSkipped += 1;
      }
      final hasActiveAudio = activeAudioItemIds.contains(bookmark.audioItemId);
      if (bookmark.deletedAt == null && !hasActiveAudio) {
        report.unavailableAudioBookmarksArchived += 1;
      }
      await _reconcile(
        subject: MemorySubjectRef(
          namespace: kSavedSentenceNamespace,
          subjectId: subjectId,
        ),
        shouldBeActive:
            bookmark.deletedAt == null && hasActiveAudio && isReviewable,
        createArchivedWhenMissing: bookmark.deletedAt != null,
        migratedAt: migratedAt,
        report: report,
      );
      return subjectId;
    } catch (error, stackTrace) {
      _recordFailure('bookmark', bookmark.id, error, stackTrace, report);
      return null;
    }
  }

  Future<String?> _migrateWord(
    SavedWord word,
    DateTime migratedAt,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) async {
    try {
      final subjectId = await _wordSubjectId(word, report);
      await _reconcile(
        subject: MemorySubjectRef(
          namespace: kSavedWordOrPhraseNamespace,
          subjectId: subjectId,
        ),
        shouldBeActive: word.deletedAt == null && word.word.trim().isNotEmpty,
        createArchivedWhenMissing: word.deletedAt != null,
        migratedAt: migratedAt,
        report: report,
      );
      return subjectId;
    } catch (error, stackTrace) {
      _recordFailure('savedWord', word.id, error, stackTrace, report);
      return null;
    }
  }

  Future<String?> _migrateSenseGroup(
    SavedSenseGroup group,
    DateTime migratedAt,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) async {
    try {
      final subjectId = await _senseGroupSubjectId(group, report);
      await _reconcile(
        subject: MemorySubjectRef(
          namespace: kSavedSenseGroupNamespace,
          subjectId: subjectId,
        ),
        shouldBeActive:
            group.deletedAt == null && group.phraseText.trim().isNotEmpty,
        createArchivedWhenMissing: group.deletedAt != null,
        migratedAt: migratedAt,
        report: report,
      );
      return subjectId;
    } catch (error, stackTrace) {
      _recordFailure('savedSenseGroup', group.id, error, stackTrace, report);
      return null;
    }
  }

  /// 归档缺少任一收藏源记录的 active 快照，避免历史孤儿进入待复习统计。
  Future<void> _archiveOrphanActiveSchedules(
    Map<String, Set<String>> subjectsByNamespace,
    DateTime migratedAt,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) async {
    final schedules = await _database.select(_database.memorySchedules).get();
    for (final schedule in schedules) {
      if (schedule.status != MemoryScheduleStatus.active.name) continue;
      final knownSubjects = subjectsByNamespace[schedule.namespace];
      if (knownSubjects == null || knownSubjects.contains(schedule.subjectId)) {
        continue;
      }
      try {
        await _scheduler.archive(
          ArchiveMemoryScheduleCommand(
            subject: MemorySubjectRef(
              namespace: schedule.namespace,
              subjectId: schedule.subjectId,
            ),
            archivedAt: migratedAt,
            expectedRevision: schedule.revision,
          ),
        );
        report.orphanSchedulesArchived += 1;
      } catch (error, stackTrace) {
        _recordFailure(
          'orphanSchedule',
          schedule.id.hashCode,
          error,
          stackTrace,
          report,
        );
      }
    }
  }

  /// 以收藏表状态为准修复调度；活跃旧收藏首次建卡即到期。
  Future<void> _reconcile({
    required MemorySubjectRef subject,
    required bool shouldBeActive,
    required bool createArchivedWhenMissing,
    required DateTime migratedAt,
    required LegacyFavoriteMemoryScheduleMigrationReport report,
  }) async {
    final existing = await _scheduler.getSchedule(subject);
    if (shouldBeActive) {
      if (existing == null) {
        await _scheduler.ensureSchedule(
          EnsureMemoryScheduleCommand(
            subject: subject,
            profile: kFsrsDefaultProfileRef,
            occurredAt: migratedAt,
          ),
        );
        report.activeSchedulesCreated += 1;
      } else if (existing.status == MemoryScheduleStatus.archived) {
        await _scheduler.restore(
          RestoreMemoryScheduleCommand(
            subject: subject,
            restoredAt: migratedAt,
            expectedRevision: existing.revision,
          ),
        );
        report.schedulesRestored += 1;
      }
      return;
    }

    if (existing == null) {
      if (!createArchivedWhenMissing) return;
      final created = await _scheduler.ensureSchedule(
        EnsureMemoryScheduleCommand(
          subject: subject,
          profile: kFsrsDefaultProfileRef,
          occurredAt: migratedAt,
        ),
      );
      await _scheduler.archive(
        ArchiveMemoryScheduleCommand(
          subject: subject,
          archivedAt: migratedAt,
          expectedRevision: created.revision,
        ),
      );
      report.archivedSchedulesCreated += 1;
      return;
    }
    if (existing.status == MemoryScheduleStatus.active) {
      await _scheduler.archive(
        ArchiveMemoryScheduleCommand(
          subject: subject,
          archivedAt: migratedAt,
          expectedRevision: existing.revision,
        ),
      );
      report.schedulesArchived += 1;
    }
  }

  Future<String> _bookmarkSubjectId(
    Bookmark bookmark,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) async {
    final current = bookmark.memorySubjectId;
    if (current != null && current.trim().isNotEmpty) return current;
    final subjectId = _uuid.v4();
    await (_database.update(_database.bookmarks)
          ..where((table) => table.id.equals(bookmark.id)))
        .write(BookmarksCompanion(memorySubjectId: Value(subjectId)));
    report.subjectIdsBackfilled += 1;
    return subjectId;
  }

  Future<String> _wordSubjectId(
    SavedWord word,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) async {
    final current = word.memorySubjectId;
    if (current != null && current.trim().isNotEmpty) return current;
    final subjectId = _uuid.v4();
    await (_database.update(_database.savedWords)
          ..where((table) => table.id.equals(word.id)))
        .write(SavedWordsCompanion(memorySubjectId: Value(subjectId)));
    report.subjectIdsBackfilled += 1;
    return subjectId;
  }

  Future<String> _senseGroupSubjectId(
    SavedSenseGroup group,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) async {
    final current = group.memorySubjectId;
    if (current != null && current.trim().isNotEmpty) return current;
    final subjectId = _uuid.v4();
    await (_database.update(_database.savedSenseGroups)
          ..where((table) => table.id.equals(group.id)))
        .write(SavedSenseGroupsCompanion(memorySubjectId: Value(subjectId)));
    report.subjectIdsBackfilled += 1;
    return subjectId;
  }

  void _recordFailure(
    String source,
    int id,
    Object error,
    StackTrace stackTrace,
    LegacyFavoriteMemoryScheduleMigrationReport report,
  ) {
    report.failures += 1;
    AppLogger.log(
      'LegacyFavoriteMemoryScheduleMigration',
      'itemFailed source=$source id=$id error=$error stack=$stackTrace',
    );
  }
}
