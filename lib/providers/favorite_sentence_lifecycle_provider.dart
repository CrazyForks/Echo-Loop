/// 收藏句与 FSRS 调度快照的一致性入口。
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/bookmark_dao.dart';
import '../database/providers.dart';
import '../features/memory_scheduler/config/memory_profiles.dart';
import '../features/memory_scheduler/domain/memory_namespaces.dart';
import '../features/memory_scheduler/domain/memory_schedule.dart';
import '../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../features/memory_scheduler/providers/memory_scheduler_providers.dart';
import '../models/sentence.dart';
import 'learning_session/favorite_review_due_count_provider.dart';

/// 统一所有收藏句新增、取消、恢复和批量清理时的调度生命周期。
final favoriteSentenceLifecycleProvider = Provider<FavoriteSentenceLifecycle>(
  (ref) => FavoriteSentenceLifecycle(ref),
);

class FavoriteSentenceLifecycle {
  FavoriteSentenceLifecycle(this._ref);

  final Ref _ref;

  /// 写入收藏句并立即创建或恢复其 FSRS 快照。
  Future<void> save(String audioItemId, Sentence sentence) async {
    await _transaction(() async {
      final dao = _ref.read(bookmarkDaoProvider);
      final now = DateTime.now();
      await dao.addBookmark(
        BookmarksCompanion(
          audioItemId: Value(audioItemId),
          memorySubjectId: Value(const Uuid().v4()),
          sentenceIndex: Value(sentence.index),
          sentenceText: Value(sentence.text),
          startTime: Value(sentence.startTime.inMilliseconds / 1000.0),
          endTime: Value(sentence.endTime.inMilliseconds / 1000.0),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      final bookmark = await dao.getByAudioAndSentence(
        audioItemId,
        sentence.index,
      );
      if (bookmark == null || bookmark.memorySubjectId == null) {
        throw StateError('收藏句缺少 memorySubjectId');
      }
      await _ensureActive(bookmark.memorySubjectId!);
    });
    _invalidateDueCount();
  }

  /// 取消一组收藏句，并归档其 active 调度快照。
  Future<void> remove(String audioItemId, Set<int> sentenceIndices) async {
    if (sentenceIndices.isEmpty) return;
    await _transaction(() async {
      final dao = _ref.read(bookmarkDaoProvider);
      for (final index in sentenceIndices) {
        final bookmark = await dao.getByAudioAndSentence(audioItemId, index);
        if (bookmark?.deletedAt == null && bookmark?.memorySubjectId != null) {
          await _archiveActive(bookmark!.memorySubjectId!);
        }
      }
      await dao.removeBookmarks(audioItemId, sentenceIndices);
    });
    _invalidateDueCount();
  }

  /// 恢复书签和其原有调度快照。
  Future<void> restore(BookmarkWithAudio item) async {
    await _transaction(() async {
      final subjectId = item.bookmark.memorySubjectId;
      if (subjectId == null || subjectId.isEmpty) {
        throw StateError('收藏句缺少 memorySubjectId');
      }
      await _ref
          .read(bookmarkDaoProvider)
          .restoreBookmark(
            item.bookmark.audioItemId,
            item.bookmark.sentenceIndex,
          );
      await _ensureActive(subjectId);
    });
    _invalidateDueCount();
  }

  /// 清空一个音频的收藏句前归档所有关联调度。
  Future<void> removeAllForAudio(String audioItemId) async {
    await _transaction(() async {
      final dao = _ref.read(bookmarkDaoProvider);
      final bookmarks = await dao.getByAudioId(audioItemId);
      for (final bookmark in bookmarks) {
        final subjectId = bookmark.memorySubjectId;
        if (subjectId != null && subjectId.isNotEmpty) {
          await _archiveActive(subjectId);
        }
      }
      await dao.removeAllForAudio(audioItemId);
    });
    _invalidateDueCount();
  }

  /// 生命周期写入提交后立即失效入口缓存，滑删和普通取消共享此时机。
  void _invalidateDueCount() =>
      _ref.invalidate(favoriteSentenceDueCountProvider);

  Future<void> _ensureActive(String subjectId) async {
    final scheduler = _ref.read(memorySchedulerProvider);
    final subject = MemorySubjectRef(
      namespace: kSavedSentenceNamespace,
      subjectId: subjectId,
    );
    final existing = await scheduler.getSchedule(subject);
    if (existing == null) {
      await scheduler.ensureSchedule(
        EnsureMemoryScheduleCommand(
          subject: subject,
          profile: kFsrsDefaultProfileRef,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
    } else if (existing.status == MemoryScheduleStatus.archived) {
      await scheduler.restore(
        RestoreMemoryScheduleCommand(
          subject: subject,
          restoredAt: DateTime.now().toUtc(),
          expectedRevision: existing.revision,
        ),
      );
    }
  }

  Future<void> _archiveActive(String subjectId) async {
    final scheduler = _ref.read(memorySchedulerProvider);
    final schedule = await scheduler.getSchedule(
      MemorySubjectRef(
        namespace: kSavedSentenceNamespace,
        subjectId: subjectId,
      ),
    );
    if (schedule == null || schedule.status != MemoryScheduleStatus.active) {
      return;
    }
    await scheduler.archive(
      ArchiveMemoryScheduleCommand(
        subject: schedule.subject,
        archivedAt: DateTime.now().toUtc(),
        expectedRevision: schedule.revision,
      ),
    );
  }

  Future<void> _transaction(Future<void> Function() operation) =>
      _ref.read(appDatabaseProvider).transaction(operation);
}
