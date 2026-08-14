/// 收藏句闪卡复习状态与控制器。
///
/// 本批次负责正面盲听、共享单句讲解背面、评分动作入口和取消收藏。所有媒体操作
/// 都用 generation 隔离，切卡、翻面和退出后，旧异步回调不能恢复播放或污染状态。
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../analytics/analytics_providers.dart';
import '../../analytics/models/event_names.dart';
import '../../database/daos/bookmark_dao.dart';
import '../../database/providers.dart';
import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/config/memory_profiles.dart';
import '../../features/memory_scheduler/domain/memory_rating.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_results.dart';
import '../../features/memory_scheduler/domain/memory_schedule.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/memory_scheduler/providers/memory_scheduler_providers.dart';
import '../../models/bookmark_review_settings.dart';
import '../bookmark_review_settings_provider.dart';
import '../../features/usage/usage_event.dart';
import '../../features/usage/usage_providers.dart';
import '../../models/bookmark_sentence.dart';
import '../../models/sentence.dart';
import '../../services/app_logger.dart';
import '../audio_engine/audio_engine_provider.dart';
import '../audio_engine/foreground_audio_engine_provider.dart';

part 'bookmark_review_provider.g.dart';

enum BookmarkReviewFace { front, back }

enum BookmarkReviewPlaybackState { idle, loading, playing, failed }

@immutable
class BookmarkReviewState {
  const BookmarkReviewState({
    this.cards = const <BookmarkSentence>[],
    this.currentIndex = 0,
    this.face = BookmarkReviewFace.front,
    this.playbackState = BookmarkReviewPlaybackState.idle,
    this.isRemoving = false,
    this.mediaError,
    this.removeError,
    this.preview,
    this.isSubmittingRating = false,
  });

  final List<BookmarkSentence> cards;
  final int currentIndex;
  final BookmarkReviewFace face;
  final BookmarkReviewPlaybackState playbackState;
  final bool isRemoving;
  final String? mediaError;
  final String? removeError;
  final MemoryRatingPreviewSet? preview;
  final bool isSubmittingRating;

  BookmarkSentence? get currentCard =>
      currentIndex >= 0 && currentIndex < cards.length
      ? cards[currentIndex]
      : null;
  int get total => cards.length;
  int get position => cards.isEmpty ? 0 : currentIndex + 1;
  bool get isCompleted => cards.isEmpty;

  BookmarkReviewState copyWith({
    List<BookmarkSentence>? cards,
    int? currentIndex,
    BookmarkReviewFace? face,
    BookmarkReviewPlaybackState? playbackState,
    bool? isRemoving,
    String? mediaError,
    bool clearMediaError = false,
    String? removeError,
    bool clearRemoveError = false,
    MemoryRatingPreviewSet? preview,
    bool clearPreview = false,
    bool? isSubmittingRating,
  }) => BookmarkReviewState(
    cards: cards ?? this.cards,
    currentIndex: currentIndex ?? this.currentIndex,
    face: face ?? this.face,
    playbackState: playbackState ?? this.playbackState,
    isRemoving: isRemoving ?? this.isRemoving,
    mediaError: clearMediaError ? null : mediaError ?? this.mediaError,
    removeError: clearRemoveError ? null : removeError ?? this.removeError,
    preview: clearPreview ? null : preview ?? this.preview,
    isSubmittingRating: isSubmittingRating ?? this.isSubmittingRating,
  );
}

@Riverpod(keepAlive: true)
class BookmarkReview extends _$BookmarkReview {
  int _generation = 0;
  late final AppLifecycleListener _lifecycleListener;

  @override
  BookmarkReviewState build() {
    final foregroundEngine = ref.read(foregroundAudioEngineProvider.notifier);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (value) {
        if (value == AppLifecycleState.paused ||
            value == AppLifecycleState.hidden ||
            value == AppLifecycleState.detached) {
          unawaited(interruptPlayback());
        }
      },
    );
    ref.onDispose(() {
      _generation++;
      _lifecycleListener.dispose();
      unawaited(foregroundEngine.stop());
    });
    return const BookmarkReviewState();
  }

  /// 建立只含 FSRS 到期收藏句的本次复习快照。
  Future<void> initialize(List<BookmarkWithAudio> bookmarks) async {
    _generation++;
    unawaited(ref.read(audioEngineProvider.notifier).stop());
    unawaited(ref.read(foregroundAudioEngineProvider.notifier).stop());

    final valid = bookmarks
        .where((item) {
          final duration = item.bookmark.endTime - item.bookmark.startTime;
          return duration > 0 &&
              item.bookmark.sentenceText.trim().isNotEmpty &&
              (item.bookmark.memorySubjectId?.isNotEmpty ?? false);
        })
        .toList(growable: false);
    final scheduler = ref.read(memorySchedulerProvider);
    final now = DateTime.now().toUtc();
    final schedules = <String, MemorySchedule>{};
    for (final item in valid) {
      final subjectId = _requireSubjectId(item.bookmark.memorySubjectId);
      final subject = _subject(subjectId);
      final existing = await scheduler.getSchedule(subject);
      final schedule = existing == null
          ? await scheduler.ensureSchedule(
              EnsureMemoryScheduleCommand(
                subject: subject,
                profile: kFsrsDefaultProfileRef,
                occurredAt: now,
              ),
            )
          : existing.status == MemoryScheduleStatus.archived
          ? await scheduler.restore(
              RestoreMemoryScheduleCommand(
                subject: subject,
                restoredAt: now,
                expectedRevision: existing.revision,
              ),
            )
          : existing;
      schedules[subjectId] = schedule;
    }
    final settings = ref.read(bookmarkReviewSettingsProvider);
    final due = valid.where((item) {
      final schedule = _scheduleFor(
        schedules,
        _requireSubjectId(item.bookmark.memorySubjectId),
      );
      return schedule.dueAt.isBefore(now) ||
          schedule.dueAt.isAtSameMomentAs(now);
    }).toList();
    _sortDue(due, schedules, settings, scheduler, now);
    final selected = await _applyDailyGoal(due, settings, now);
    final cards = selected.map(_toCard).toList(growable: false);
    state = BookmarkReviewState(cards: List.unmodifiable(cards));
    ref.read(analyticsServiceProvider).track(Events.bookmarkReviewStart, {
      EventParams.totalSentencesCount: cards.length,
    });
  }

  BookmarkSentence _toCard(BookmarkWithAudio item) => BookmarkSentence(
    sentence: Sentence(
      index: item.bookmark.sentenceIndex,
      text: item.bookmark.sentenceText,
      startTime: Duration(
        milliseconds: (item.bookmark.startTime * 1000).round(),
      ),
      endTime: Duration(milliseconds: (item.bookmark.endTime * 1000).round()),
      isBookmarked: true,
    ),
    audioItemId: item.bookmark.audioItemId,
    audioName: item.audioName,
    originalSentenceIndex: item.bookmark.sentenceIndex,
    memorySubjectId: _requireSubjectId(item.bookmark.memorySubjectId),
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
    BookmarkReviewSettings settings,
    MemoryScheduler scheduler,
    DateTime now,
  ) {
    if (settings.order == BookmarkReviewOrder.random) {
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
      if (settings.order == BookmarkReviewOrder.dueAt) {
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
      final leftScore = scheduler.retrievability(left, now);
      final rightScore = scheduler.retrievability(right, now);
      final score = leftScore.compareTo(rightScore);
      return score != 0 ? score : left.dueAt.compareTo(right.dueAt);
    });
  }

  Future<List<BookmarkWithAudio>> _applyDailyGoal(
    List<BookmarkWithAudio> due,
    BookmarkReviewSettings settings,
    DateTime now,
  ) async {
    final goal = settings.dailyReviewGoal;
    if (goal == null) return due;
    final local = now.toLocal();
    final day =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final db = ref.read(appDatabaseProvider);
    final rows = await db
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
      final inserted = await db.customUpdate(
        'INSERT OR IGNORE INTO bookmark_review_queue_entries(subject_id, local_date, enqueued_at) VALUES (?, ?, ?)',
        variables: [
          Variable<String>(subjectId),
          Variable<String>(day),
          Variable<DateTime>(now),
        ],
        updates: {db.bookmarkReviewQueueEntries},
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

  Future<void> startCurrentCard() => replayCurrent();

  /// 立即废弃旧播放，再从当前句起点播放。
  Future<void> replayCurrent() async {
    final card = state.currentCard;
    if (card == null) return;
    final generation = ++_generation;
    final engine = ref.read(foregroundAudioEngineProvider.notifier);
    await engine.stop();
    if (!_isCurrent(generation, card)) return;
    state = state.copyWith(
      playbackState: BookmarkReviewPlaybackState.loading,
      clearMediaError: true,
    );
    try {
      if (!_isCurrent(generation, card)) return;
      state = state.copyWith(
        playbackState: BookmarkReviewPlaybackState.playing,
      );
      await engine.playRangeForAudio(
        card.audioItemId,
        card.sentence.startTime,
        card.sentence.endTime,
        speed: 1.0,
      );
      if (!_isCurrent(generation, card)) return;
      state = state.copyWith(playbackState: BookmarkReviewPlaybackState.idle);
    } catch (error, stackTrace) {
      if (!_isCurrent(generation, card)) return;
      AppLogger.log(
        'FavoriteSentenceReview',
        'media failed error=$error\n$stackTrace',
      );
      state = state.copyWith(
        playbackState: BookmarkReviewPlaybackState.failed,
        mediaError: 'audio_unavailable',
      );
    }
  }

  /// 切换当前句的播放状态；收藏复习背面仅支持从句首播放或停止。
  Future<void> toggleCurrentPlayback() async {
    final playbackState = state.playbackState;
    if (playbackState == BookmarkReviewPlaybackState.loading ||
        playbackState == BookmarkReviewPlaybackState.playing) {
      await interruptPlayback();
      return;
    }
    await replayCurrent();
  }

  Future<void> revealBack() async {
    if (state.currentCard == null || state.face != BookmarkReviewFace.front) {
      return;
    }
    await interruptPlayback();
    state = state.copyWith(face: BookmarkReviewFace.back, clearPreview: true);
    final card = state.currentCard;
    if (card == null) return;
    try {
      final preview = await ref
          .read(memorySchedulerProvider)
          .previewRatings(
            PreviewMemoryRatingsQuery(
              subject: _subject(card.memorySubjectId),
              reviewedAt: DateTime.now().toUtc(),
              expectedRevision: null,
            ),
          );
      if (state.currentCard == card && state.face == BookmarkReviewFace.back) {
        state = state.copyWith(preview: preview);
      }
    } catch (error) {
      AppLogger.log('FavoriteSentenceReview', 'preview failed error=$error');
    }
  }

  /// 接收背面评分动作；调度接入前只保留统一的映射入口和日志。
  Future<void> selectRating(MemoryRating rating) async {
    final card = state.currentCard;
    if (card == null || state.face != BookmarkReviewFace.back) return;
    if (state.isSubmittingRating) return;
    final previews = state.preview;
    if (previews == null) return;
    final preview = _previewFor(previews, rating);
    state = state.copyWith(isSubmittingRating: true);
    try {
      await ref
          .read(memorySchedulerProvider)
          .review(
            ReviewMemoryCommand(
              subject: _subject(card.memorySubjectId),
              rating: rating,
              preview: preview,
              reviewedAt: preview.reviewedAt,
              responseTime: Duration.zero,
              operationId:
                  'favorite-${card.memorySubjectId}-${DateTime.now().microsecondsSinceEpoch}',
              expectedRevision: state.preview?.revision ?? 0,
            ),
          );
      final cards = List<BookmarkSentence>.of(state.cards)..remove(card);
      state = BookmarkReviewState(cards: List.unmodifiable(cards));
      if (cards.isNotEmpty) unawaited(startCurrentCard());
    } catch (error) {
      AppLogger.log('FavoriteSentenceReview', 'rating failed error=$error');
      state = state.copyWith(isSubmittingRating: false);
    }
  }

  MemoryRatingPreview _previewFor(
    MemoryRatingPreviewSet previews,
    MemoryRating rating,
  ) => switch (rating) {
    MemoryRating.again => previews.again,
    MemoryRating.hard => previews.hard,
    MemoryRating.good => previews.good,
    MemoryRating.easy => previews.easy,
  };

  Future<void> removeCurrentBookmark() async {
    final card = state.currentCard;
    if (card == null || state.isRemoving) return;
    await interruptPlayback();
    state = state.copyWith(isRemoving: true, clearRemoveError: true);
    try {
      await ref
          .read(bookmarkDaoProvider)
          .removeBookmark(card.audioItemId, card.originalSentenceIndex);
      final schedule = await ref
          .read(memorySchedulerProvider)
          .getSchedule(_subject(card.memorySubjectId));
      if (schedule != null && schedule.status == MemoryScheduleStatus.active) {
        await ref
            .read(memorySchedulerProvider)
            .archive(
              ArchiveMemoryScheduleCommand(
                subject: schedule.subject,
                archivedAt: DateTime.now().toUtc(),
                expectedRevision: schedule.revision,
              ),
            );
      }
      final cards = List<BookmarkSentence>.of(state.cards)..remove(card);
      final nextIndex = cards.isEmpty
          ? 0
          : state.currentIndex.clamp(0, cards.length - 1);
      state = BookmarkReviewState(
        cards: List.unmodifiable(cards),
        currentIndex: nextIndex,
      );
      if (cards.isNotEmpty) unawaited(startCurrentCard());
    } catch (error, stackTrace) {
      AppLogger.log(
        'FavoriteSentenceReview',
        'unsave failed error=$error\n$stackTrace',
      );
      state = state.copyWith(isRemoving: false, removeError: 'unsave_failed');
    }
  }

  Future<void> interruptPlayback() async {
    _generation++;
    if (state.playbackState != BookmarkReviewPlaybackState.idle) {
      state = state.copyWith(playbackState: BookmarkReviewPlaybackState.idle);
    }
    await ref.read(foregroundAudioEngineProvider.notifier).stop();
  }

  Future<void> disposeSession() async {
    await interruptPlayback();
    if (state.cards.isNotEmpty) {
      ref
          .read(usageTrackerProvider)
          .record(
            UsageEvent.bookmarkSentenceReviewCompleted,
            analyticsParams: {
              EventParams.totalSentencesCount: state.cards.length,
              EventParams.durationMs: 0,
            },
          );
    }
    state = const BookmarkReviewState();
  }

  bool _isCurrent(int generation, BookmarkSentence card) =>
      generation == _generation && identical(state.currentCard, card);
}
