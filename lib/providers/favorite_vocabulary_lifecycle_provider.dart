/// 收藏词汇与记忆调度的一致性入口。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/providers.dart';
import '../features/memory_scheduler/config/memory_profiles.dart';
import '../features/memory_scheduler/domain/memory_namespaces.dart';
import '../features/memory_scheduler/domain/memory_schedule.dart';
import '../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../features/memory_scheduler/providers/memory_scheduler_providers.dart';
import 'learning_session/favorite_review_due_count_provider.dart';

/// 统一所有词汇/意群取消与恢复收藏时的调度生命周期。
final favoriteVocabularyLifecycleProvider =
    Provider<FavoriteVocabularyLifecycle>(
      (ref) => FavoriteVocabularyLifecycle(ref),
    );

class FavoriteVocabularyLifecycle {
  FavoriteVocabularyLifecycle(this._ref);

  final Ref _ref;

  /// 软删除单词，并归档其仍 active 的记忆调度。
  Future<void> removeWord(String word) async {
    final dao = _ref.read(savedWordDaoProvider);
    final item = await dao.getByWord(word);
    if (item == null || item.deletedAt != null) return;
    await _remove(
      namespace: kSavedWordOrPhraseNamespace,
      subjectId: item.memorySubjectId,
      removeContent: () => dao.removeWord(word),
    );
    _invalidateDueCount();
  }

  /// 软删除意群，并归档其仍 active 的记忆调度。
  Future<void> removeSenseGroup(String phraseText) async {
    final dao = _ref.read(savedSenseGroupDaoProvider);
    final item = await dao.getByPhraseText(phraseText);
    if (item == null || item.deletedAt != null) return;
    await _remove(
      namespace: kSavedSenseGroupNamespace,
      subjectId: item.memorySubjectId,
      removeContent: () => dao.removeSenseGroup(phraseText),
    );
    _invalidateDueCount();
  }

  /// 从回收站恢复单词，并恢复既有归档调度。
  Future<void> restoreWord(String word) async {
    final dao = _ref.read(savedWordDaoProvider);
    final item = await dao.getByWord(word);
    if (item == null || item.deletedAt == null) return;
    await _restore(
      namespace: kSavedWordOrPhraseNamespace,
      subjectId: item.memorySubjectId,
      restoreContent: () => dao.restoreWord(word),
      undoRestoreContent: () => dao.removeWord(word),
    );
    _invalidateDueCount();
  }

  /// 从回收站恢复意群，并恢复既有归档调度。
  Future<void> restoreSenseGroup(String phraseText) async {
    final dao = _ref.read(savedSenseGroupDaoProvider);
    final item = await dao.getByPhraseText(phraseText);
    if (item == null || item.deletedAt == null) return;
    await _restore(
      namespace: kSavedSenseGroupNamespace,
      subjectId: item.memorySubjectId,
      restoreContent: () => dao.restoreSenseGroup(phraseText),
      undoRestoreContent: () => dao.removeSenseGroup(phraseText),
    );
    _invalidateDueCount();
  }

  /// 新收藏或再次收藏后恢复既有调度；新内容立即建立可统计的调度快照。
  Future<void> restoreWordSchedule(String word) async {
    final item = await _ref.read(savedWordDaoProvider).getByWord(word);
    await _restoreSchedule(kSavedWordOrPhraseNamespace, item?.memorySubjectId);
    _invalidateDueCount();
  }

  /// 新收藏或再次收藏后恢复既有调度；新内容立即建立可统计的调度快照。
  Future<void> restoreSenseGroupSchedule(String phraseText) async {
    final item = await _ref
        .read(savedSenseGroupDaoProvider)
        .getByPhraseText(phraseText);
    await _restoreSchedule(kSavedSenseGroupNamespace, item?.memorySubjectId);
    _invalidateDueCount();
  }

  Future<void> _remove({
    required String namespace,
    required String? subjectId,
    required Future<void> Function() removeContent,
  }) async {
    final archived = await _archiveSchedule(namespace, subjectId);
    try {
      await removeContent();
    } catch (_) {
      if (archived != null) {
        await _restoreArchivedSchedule(archived);
      }
      rethrow;
    }
  }

  Future<void> _restore({
    required String namespace,
    required String? subjectId,
    required Future<void> Function() restoreContent,
    required Future<void> Function() undoRestoreContent,
  }) async {
    await restoreContent();
    try {
      await _restoreSchedule(namespace, subjectId);
    } catch (_) {
      await undoRestoreContent();
      rethrow;
    }
  }

  Future<MemorySchedule?> _archiveSchedule(
    String namespace,
    String? subjectId,
  ) async {
    if (subjectId == null || subjectId.isEmpty) return null;
    final scheduler = _ref.read(memorySchedulerProvider);
    final schedule = await scheduler.getSchedule(
      MemorySubjectRef(namespace: namespace, subjectId: subjectId),
    );
    if (schedule == null || schedule.status != MemoryScheduleStatus.active) {
      return null;
    }
    return scheduler.archive(
      ArchiveMemoryScheduleCommand(
        subject: schedule.subject,
        archivedAt: DateTime.now().toUtc(),
        expectedRevision: schedule.revision,
      ),
    );
  }

  Future<void> _restoreSchedule(String namespace, String? subjectId) async {
    if (subjectId == null || subjectId.isEmpty) return;
    final scheduler = _ref.read(memorySchedulerProvider);
    final schedule = await scheduler.getSchedule(
      MemorySubjectRef(namespace: namespace, subjectId: subjectId),
    );
    if (schedule == null) {
      await scheduler.ensureSchedule(
        EnsureMemoryScheduleCommand(
          subject: MemorySubjectRef(namespace: namespace, subjectId: subjectId),
          profile: kFsrsDefaultProfileRef,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
      return;
    }
    if (schedule.status != MemoryScheduleStatus.archived) {
      return;
    }
    await _restoreArchivedSchedule(schedule);
  }

  Future<void> _restoreArchivedSchedule(MemorySchedule schedule) => _ref
      .read(memorySchedulerProvider)
      .restore(
        RestoreMemoryScheduleCommand(
          subject: schedule.subject,
          restoredAt: DateTime.now().toUtc(),
          expectedRevision: schedule.revision,
        ),
      );

  /// 所有词汇收藏生命周期完成后统一刷新入口数量。
  void _invalidateDueCount() =>
      _ref.invalidate(favoriteVocabularyDueCountProvider);
}
