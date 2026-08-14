/// 收藏句复习的调度队列来源。
library;

import 'package:drift/drift.dart';

import '../../database/app_database.dart' hide MemorySchedule;
import '../../database/daos/bookmark_dao.dart';
import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/config/memory_profiles.dart';
import '../../features/memory_scheduler/domain/memory_schedule.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/bookmark_review_settings.dart';
import '../../models/bookmark_sentence.dart';
import '../../models/sentence.dart';

/// 确保调度存在、按到期时间过滤、按设置排序并应用每日新卡上限，
/// 产出本次收藏句复习会话的固定快照。
///
/// 逻辑照搬自重构前 `BookmarkReview.initialize()`，只是把宿主从手写 Notifier
/// 换成 `FlashcardDeckSource<BookmarkSentence>`，查询条件和排序规则不变。
final class FavoriteSentenceDeckSource
    implements FlashcardDeckSource<BookmarkSentence> {
  FavoriteSentenceDeckSource({
    required List<BookmarkWithAudio> bookmarks,
    required MemoryScheduler scheduler,
    required BookmarkReviewSettings settings,
    required AppDatabase database,
    DateTime Function()? now,
  }) : _bookmarks = bookmarks,
       _scheduler = scheduler,
       _settings = settings,
       _database = database,
       _now = now ?? DateTime.now;

  final List<BookmarkWithAudio> _bookmarks;
  final MemoryScheduler _scheduler;
  final BookmarkReviewSettings _settings;
  final AppDatabase _database;
  final DateTime Function() _now;

  @override
  Future<List<ScheduledFlashcard<BookmarkSentence>>> load() async {
    final valid = _bookmarks
        .where((item) {
          final duration = item.bookmark.endTime - item.bookmark.startTime;
          return duration > 0 &&
              item.bookmark.sentenceText.trim().isNotEmpty &&
              (item.bookmark.memorySubjectId?.isNotEmpty ?? false);
        })
        .toList(growable: false);

    final now = _now().toUtc();
    final schedules = <String, MemorySchedule>{};
    for (final item in valid) {
      final subjectId = _requireSubjectId(item.bookmark.memorySubjectId);
      final subject = _subject(subjectId);
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
      schedules[subjectId] = schedule;
    }

    final due = valid.where((item) {
      final schedule = _scheduleFor(
        schedules,
        _requireSubjectId(item.bookmark.memorySubjectId),
      );
      return schedule.dueAt.isBefore(now) ||
          schedule.dueAt.isAtSameMomentAs(now);
    }).toList();
    _sortDue(due, schedules, now);
    final selected = await _applyDailyGoal(due, now);
    return selected
        .map((item) => _toScheduledCard(item, schedules))
        .toList(growable: false);
  }

  ScheduledFlashcard<BookmarkSentence> _toScheduledCard(
    BookmarkWithAudio item,
    Map<String, MemorySchedule> schedules,
  ) {
    final subjectId = _requireSubjectId(item.bookmark.memorySubjectId);
    final schedule = _scheduleFor(schedules, subjectId);
    return ScheduledFlashcard<BookmarkSentence>(
      subject: schedule.subject,
      content: _toCard(item, subjectId),
      scheduleRevision: schedule.revision,
    );
  }

  BookmarkSentence _toCard(BookmarkWithAudio item, String subjectId) =>
      BookmarkSentence(
        sentence: Sentence(
          index: item.bookmark.sentenceIndex,
          text: item.bookmark.sentenceText,
          startTime: Duration(
            milliseconds: (item.bookmark.startTime * 1000).round(),
          ),
          endTime: Duration(
            milliseconds: (item.bookmark.endTime * 1000).round(),
          ),
          isBookmarked: true,
        ),
        audioItemId: item.bookmark.audioItemId,
        audioName: item.audioName,
        originalSentenceIndex: item.bookmark.sentenceIndex,
        memorySubjectId: subjectId,
      );

  MemorySubjectRef _subject(String id) =>
      MemorySubjectRef(namespace: 'favorite_sentence', subjectId: id);

  String _requireSubjectId(String? value) {
    if (value == null || value.isEmpty) {
      throw StateError('收藏句缺少 memorySubjectId');
    }
    return value;
  }

  MemorySchedule _scheduleFor(
    Map<String, MemorySchedule> schedules,
    String id,
  ) {
    final schedule = schedules[id];
    if (schedule == null) throw StateError('Missing schedule for $id');
    return schedule;
  }

  void _sortDue(
    List<BookmarkWithAudio> items,
    Map<String, MemorySchedule> schedules,
    DateTime now,
  ) {
    if (_settings.order == BookmarkReviewOrder.random) {
      items.shuffle();
      return;
    }
    items.sort((a, b) {
      final left = _scheduleFor(
        schedules,
        _requireSubjectId(a.bookmark.memorySubjectId),
      );
      final right = _scheduleFor(
        schedules,
        _requireSubjectId(b.bookmark.memorySubjectId),
      );
      if (_settings.order == BookmarkReviewOrder.dueAt) {
        final due = left.dueAt.compareTo(right.dueAt);
        return due != 0
            ? due
            : _requireSubjectId(
                a.bookmark.memorySubjectId,
              ).compareTo(_requireSubjectId(b.bookmark.memorySubjectId));
      }
      final leftNew = left.reviewCount == 0;
      final rightNew = right.reviewCount == 0;
      if (leftNew != rightNew) return leftNew ? 1 : -1;
      if (leftNew) return a.bookmark.createdAt.compareTo(b.bookmark.createdAt);
      final leftScore = _scheduler.retrievability(left, now);
      final rightScore = _scheduler.retrievability(right, now);
      final score = leftScore.compareTo(rightScore);
      return score != 0 ? score : left.dueAt.compareTo(right.dueAt);
    });
  }

  Future<List<BookmarkWithAudio>> _applyDailyGoal(
    List<BookmarkWithAudio> due,
    DateTime now,
  ) async {
    final goal = _settings.dailyReviewGoal;
    if (goal == null) return due;
    final local = now.toLocal();
    final day =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final rows = await _database
        .customSelect(
          'SELECT subject_id FROM bookmark_review_queue_entries WHERE local_date = ?',
          variables: [Variable<String>(day)],
        )
        .get();
    final enrolled = rows
        .map((row) => row.data['subject_id'] as String)
        .toSet();
    var remaining = goal - enrolled.length;
    final result = <BookmarkWithAudio>[];
    for (final item in due) {
      final subjectId = _requireSubjectId(item.bookmark.memorySubjectId);
      if (enrolled.contains(subjectId)) {
        result.add(item);
        continue;
      }
      if (remaining <= 0) continue;
      final inserted = await _database.customUpdate(
        'INSERT OR IGNORE INTO bookmark_review_queue_entries(subject_id, local_date, enqueued_at) VALUES (?, ?, ?)',
        variables: [
          Variable<String>(subjectId),
          Variable<String>(day),
          Variable<DateTime>(now),
        ],
        updates: {_database.bookmarkReviewQueueEntries},
      );
      if (inserted > 0) {
        result.add(item);
        enrolled.add(subjectId);
        remaining--;
      } else if (enrolled.contains(subjectId)) {
        result.add(item);
      }
    }
    return result;
  }
}
