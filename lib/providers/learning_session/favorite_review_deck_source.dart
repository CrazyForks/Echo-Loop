/// 收藏复习共用的调度队列来源。
library;

import 'package:drift/drift.dart';

import '../../database/app_database.dart' hide MemorySchedule;
import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/config/memory_profiles.dart';
import '../../features/memory_scheduler/domain/memory_schedule.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/favorite_review_settings.dart';

/// 已纳入收藏复习调度的内容适配项。
final class FavoriteReviewDeckItem<T> {
  const FavoriteReviewDeckItem({
    required this.content,
    required this.subject,
    required this.createdAt,
  });

  final T content;
  final MemorySubjectRef subject;
  final DateTime createdAt;
}

/// 对任意收藏内容执行同一套 FSRS 入队、过滤、排序和预算逻辑。
final class FavoriteReviewDeckSource<T> implements FlashcardDeckSource<T> {
  FavoriteReviewDeckSource({
    required List<FavoriteReviewDeckItem<T>> items,
    required MemoryScheduler scheduler,
    required FavoriteReviewSettings settings,
    required int? dailyReviewGoal,
    required List<String> budgetNamespaces,
    required AppDatabase database,
    DateTime Function()? now,
  }) : _items = items,
       _scheduler = scheduler,
       _settings = settings,
       _dailyReviewGoal = dailyReviewGoal,
       _budgetNamespaces = budgetNamespaces,
       _database = database,
       _now = now ?? DateTime.now;

  final List<FavoriteReviewDeckItem<T>> _items;
  final MemoryScheduler _scheduler;
  final FavoriteReviewSettings _settings;
  final int? _dailyReviewGoal;
  final List<String> _budgetNamespaces;
  final AppDatabase _database;
  final DateTime Function() _now;

  @override
  Future<List<ScheduledFlashcard<T>>> load() async {
    final now = _now().toUtc();
    final schedules = <MemorySubjectRef, MemorySchedule>{};
    for (final item in _items) {
      final existing = await _scheduler.getSchedule(item.subject);
      final schedule = existing == null
          ? await _scheduler.ensureSchedule(
              EnsureMemoryScheduleCommand(
                subject: item.subject,
                profile: kFsrsDefaultProfileRef,
                occurredAt: now,
              ),
            )
          : existing.status == MemoryScheduleStatus.archived
          ? await _scheduler.restore(
              RestoreMemoryScheduleCommand(
                subject: item.subject,
                restoredAt: now,
                expectedRevision: existing.revision,
              ),
            )
          : existing;
      schedules[item.subject] = schedule;
    }
    final due = _items.where((item) {
      final dueAt = schedules[item.subject]!.dueAt;
      return !dueAt.isAfter(now);
    }).toList();
    _sortDue(due, schedules, now);
    final selected = await _applyDailyGoal(due, now);
    return selected
        .map(
          (item) => ScheduledFlashcard<T>(
            subject: item.subject,
            content: item.content,
            scheduleRevision: schedules[item.subject]!.revision,
          ),
        )
        .toList(growable: false);
  }

  void _sortDue(
    List<FavoriteReviewDeckItem<T>> items,
    Map<MemorySubjectRef, MemorySchedule> schedules,
    DateTime now,
  ) {
    if (_settings.order == FavoriteReviewOrder.random) {
      items.shuffle();
      return;
    }
    items.sort((a, b) {
      final left = schedules[a.subject]!;
      final right = schedules[b.subject]!;
      if (_settings.order == FavoriteReviewOrder.dueAt) {
        final due = left.dueAt.compareTo(right.dueAt);
        return due != 0 ? due : _key(a.subject).compareTo(_key(b.subject));
      }
      final leftNew = left.reviewCount == 0;
      final rightNew = right.reviewCount == 0;
      if (leftNew != rightNew) return leftNew ? 1 : -1;
      if (leftNew) return a.createdAt.compareTo(b.createdAt);
      final score = _scheduler
          .retrievability(left, now)
          .compareTo(_scheduler.retrievability(right, now));
      return score != 0 ? score : left.dueAt.compareTo(right.dueAt);
    });
  }

  Future<List<FavoriteReviewDeckItem<T>>> _applyDailyGoal(
    List<FavoriteReviewDeckItem<T>> due,
    DateTime now,
  ) async {
    final goal = _dailyReviewGoal;
    if (goal == null) return due;
    final local = now.toLocal();
    final day =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final placeholders = _budgetNamespaces.map((_) => '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT namespace, subject_id FROM memory_review_queue_entries WHERE namespace IN ($placeholders) AND local_date = ?',
          variables: [
            for (final namespace in _budgetNamespaces)
              Variable<String>(namespace),
            Variable<String>(day),
          ],
        )
        .get();
    final enrolled = rows
        .map((row) => '${row.data['namespace']}:${row.data['subject_id']}')
        .toSet();
    var remaining = goal - enrolled.length;
    final result = <FavoriteReviewDeckItem<T>>[];
    for (final item in due) {
      final key = _key(item.subject);
      if (enrolled.contains(key)) {
        result.add(item);
        continue;
      }
      if (remaining <= 0) continue;
      final inserted = await _database.customUpdate(
        'INSERT OR IGNORE INTO memory_review_queue_entries(namespace, subject_id, local_date, enqueued_at) VALUES (?, ?, ?, ?)',
        variables: [
          Variable<String>(item.subject.namespace),
          Variable<String>(item.subject.subjectId),
          Variable<String>(day),
          Variable<DateTime>(now),
        ],
        updates: {_database.memoryReviewQueueEntries},
      );
      if (inserted > 0) {
        result.add(item);
        enrolled.add(key);
        remaining--;
      } else if (enrolled.contains(key)) {
        result.add(item);
      }
    }
    return result;
  }

  String _key(MemorySubjectRef subject) =>
      '${subject.namespace}:${subject.subjectId}';
}
