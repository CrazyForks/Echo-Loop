/// 收藏词汇（单词 + 意群）复习的调度队列来源。
library;

import 'package:drift/drift.dart';

import '../../database/app_database.dart' hide MemorySchedule;
import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/config/memory_profiles.dart';
import '../../features/memory_scheduler/domain/memory_schedule.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/favorite_vocabulary_review_settings.dart';
import '../../models/flashcard_item.dart';

/// 单词、多词词组（作为 [SavedWord]）与意群统一按"收藏词汇"一套调度处理，
/// 与收藏句共用同一 FSRS 基础设施。逻辑结构照抄
/// `FavoriteSentenceDeckSource`：ensure/restore、到期过滤、排序、每日新卡
/// 上限；区别只在于内容按各自 namespace（`saved_word`/`saved_phrase`）
/// 建立调度身份，且单词和意群共用同一个每日新卡预算。
final class FavoriteVocabularyDeckSource
    implements FlashcardDeckSource<FlashcardItem> {
  FavoriteVocabularyDeckSource({
    required List<SavedWord> words,
    required List<SavedSenseGroup> phrases,
    required MemoryScheduler scheduler,
    required FavoriteVocabularyReviewSettings settings,
    required AppDatabase database,
    DateTime Function()? now,
  }) : _words = words,
       _phrases = phrases,
       _scheduler = scheduler,
       _settings = settings,
       _database = database,
       _now = now ?? DateTime.now;

  final List<SavedWord> _words;
  final List<SavedSenseGroup> _phrases;
  final MemoryScheduler _scheduler;
  final FavoriteVocabularyReviewSettings _settings;
  final AppDatabase _database;
  final DateTime Function() _now;

  /// 单词与意群共用同一个每日新卡预算，对用户来说都是"收藏词汇"。
  static const _dailyGoalNamespaces = ['saved_word', 'saved_phrase'];

  @override
  Future<List<ScheduledFlashcard<FlashcardItem>>> load() async {
    final valid = <FlashcardItem>[
      for (final word in _words) FlashcardWordItem(savedWord: word),
      for (final phrase in _phrases) FlashcardPhraseItem(savedPhrase: phrase),
    ].where((item) {
      final subjectId = item.memorySubjectId;
      return item.displayText.trim().isNotEmpty &&
          (subjectId?.isNotEmpty ?? false);
    }).toList(growable: false);

    final now = _now().toUtc();
    final schedules = <String, MemorySchedule>{};
    for (final item in valid) {
      final subjectId = _requireSubjectId(item.memorySubjectId);
      final subject = MemorySubjectRef(
        namespace: item.namespace,
        subjectId: subjectId,
      );
      final existing = await _scheduler.getSchedule(subject);
      final schedule = existing == null
          ? await _scheduler.ensureSchedule(
              EnsureMemoryScheduleCommand(
                subject: subject,
                profile: kFsrsDefaultProfileRef,
                occurredAt: now,
              ),
            )
          : existing.status == MemoryScheduleStatus.archived
          ? await _scheduler.restore(
              RestoreMemoryScheduleCommand(
                subject: subject,
                restoredAt: now,
                expectedRevision: existing.revision,
              ),
            )
          : existing;
      schedules[_key(item)] = schedule;
    }

    final due = valid.where((item) {
      final schedule = _scheduleFor(schedules, item);
      return schedule.dueAt.isBefore(now) ||
          schedule.dueAt.isAtSameMomentAs(now);
    }).toList();
    _sortDue(due, schedules, now);
    final selected = await _applyDailyGoal(due, now);
    return selected
        .map((item) => _toScheduledCard(item, schedules))
        .toList(growable: false);
  }

  ScheduledFlashcard<FlashcardItem> _toScheduledCard(
    FlashcardItem item,
    Map<String, MemorySchedule> schedules,
  ) {
    final schedule = _scheduleFor(schedules, item);
    return ScheduledFlashcard<FlashcardItem>(
      subject: schedule.subject,
      content: item,
      scheduleRevision: schedule.revision,
    );
  }

  String _key(FlashcardItem item) => '${item.namespace}:${item.memorySubjectId}';

  String _requireSubjectId(String? value) {
    if (value == null || value.isEmpty) {
      throw StateError('收藏词汇缺少 memorySubjectId');
    }
    return value;
  }

  MemorySchedule _scheduleFor(
    Map<String, MemorySchedule> schedules,
    FlashcardItem item,
  ) {
    final schedule = schedules[_key(item)];
    if (schedule == null) {
      throw StateError('Missing schedule for ${_key(item)}');
    }
    return schedule;
  }

  void _sortDue(
    List<FlashcardItem> items,
    Map<String, MemorySchedule> schedules,
    DateTime now,
  ) {
    if (_settings.order == FavoriteVocabularyReviewOrder.random) {
      items.shuffle();
      return;
    }
    items.sort((a, b) {
      final left = _scheduleFor(schedules, a);
      final right = _scheduleFor(schedules, b);
      if (_settings.order == FavoriteVocabularyReviewOrder.dueAt) {
        final due = left.dueAt.compareTo(right.dueAt);
        return due != 0 ? due : _key(a).compareTo(_key(b));
      }
      final leftNew = left.reviewCount == 0;
      final rightNew = right.reviewCount == 0;
      if (leftNew != rightNew) return leftNew ? 1 : -1;
      if (leftNew) return a.createdAt.compareTo(b.createdAt);
      final leftScore = _scheduler.retrievability(left, now);
      final rightScore = _scheduler.retrievability(right, now);
      final score = leftScore.compareTo(rightScore);
      return score != 0 ? score : left.dueAt.compareTo(right.dueAt);
    });
  }

  Future<List<FlashcardItem>> _applyDailyGoal(
    List<FlashcardItem> due,
    DateTime now,
  ) async {
    final goal = _settings.dailyReviewGoal;
    if (goal == null) return due;
    final local = now.toLocal();
    final day =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final placeholders = _dailyGoalNamespaces.map((_) => '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT namespace, subject_id FROM memory_review_queue_entries WHERE namespace IN ($placeholders) AND local_date = ?',
          variables: [
            for (final namespace in _dailyGoalNamespaces)
              Variable<String>(namespace),
            Variable<String>(day),
          ],
        )
        .get();
    final enrolled = rows
        .map((row) => '${row.data['namespace']}:${row.data['subject_id']}')
        .toSet();
    var remaining = goal - enrolled.length;
    final result = <FlashcardItem>[];
    for (final item in due) {
      final key = _key(item);
      if (enrolled.contains(key)) {
        result.add(item);
        continue;
      }
      if (remaining <= 0) continue;
      final inserted = await _database.customUpdate(
        'INSERT OR IGNORE INTO memory_review_queue_entries(namespace, subject_id, local_date, enqueued_at) VALUES (?, ?, ?, ?)',
        variables: [
          Variable<String>(item.namespace),
          Variable<String>(_requireSubjectId(item.memorySubjectId)),
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
}
