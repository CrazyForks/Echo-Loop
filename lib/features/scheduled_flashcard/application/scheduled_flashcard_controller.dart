/// 调度 Flashcard 的异步应用控制器。
library;

import 'dart:async';

import 'package:clock/clock.dart';

import '../../memory_scheduler/domain/memory_rating.dart';
import '../../memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../memory_scheduler/domain/memory_scheduler_exceptions.dart';
import '../../memory_scheduler/domain/memory_scheduler_results.dart';
import '../../memory_scheduler/application/memory_scheduler.dart';
import '../domain/scheduled_flashcard.dart';
import 'scheduled_flashcard_engine.dart';

/// 为 controller 生成幂等操作 ID。
abstract interface class FlashcardOperationIdGenerator {
  String newId();
}

/// 默认操作 ID 生成器，不依赖 Flutter 或 UUID 插件。
final class IncrementingFlashcardOperationIdGenerator
    implements FlashcardOperationIdGenerator {
  int _next = 0;
  @override
  String newId() => 'scheduled-flashcard-${++_next}';
}

/// 调度 Flashcard 的 IO 编排层。
final class ScheduledFlashcardController<T> {
  ScheduledFlashcardController({
    required FlashcardDeckSource<T> deckSource,
    required FlashcardRatingPort ratingPort,
    Clock? clock,
    FlashcardOperationIdGenerator? operationIdGenerator,
    void Function(String message)? logger,
  }) : _deckSource = deckSource,
       _ratingPort = ratingPort,
       _clock = clock ?? const Clock(),
       _operationIdGenerator =
           operationIdGenerator ?? IncrementingFlashcardOperationIdGenerator(),
       _logger = logger ?? _ignoreLog;

  final FlashcardDeckSource<T> _deckSource;
  final FlashcardRatingPort _ratingPort;
  final Clock _clock;
  final FlashcardOperationIdGenerator _operationIdGenerator;
  final void Function(String message) _logger;
  final ScheduledFlashcardEngine<T> _engine = ScheduledFlashcardEngine<T>();
  final List<void Function()> _listeners = <void Function()>[];
  int _generation = 0;
  DateTime? _promptedAt;
  String? _pendingOperationId;
  bool _disposed = false;

  ScheduledFlashcardSessionState<T> get state => _engine.state;
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  Future<void> load() async {
    final generation = ++_generation;
    _log('load.start generation=$generation');
    _engine.setError(StateError('loading'));
    _notify();
    try {
      final deck = await _deckSource.load();
      if (!_valid(generation)) {
        _log('load.discarded generation=$generation');
        return;
      }
      _engine.setDeck(deck);
      _log('load.success generation=$generation cards=${deck.length}');
      _promptedAt = _clock.now().toUtc();
      _notify();
    } catch (error) {
      if (!_valid(generation)) return;
      _log('load.error generation=$generation error=$error');
      _engine.setError(error);
      _notify();
    }
  }

  void revealAnswer() {
    _log('reveal card=${state.current?.subject.subjectId}');
    _engine.revealAnswer();
    _notify();
  }

  Future<void> preview() async {
    final card = state.current;
    if (card == null || state.phase != ScheduledFlashcardPhase.answer) return;
    final generation = _generation;
    _log(
      'preview.start card=${card.subject.subjectId} revision=${card.scheduleRevision} generation=$generation',
    );
    try {
      final result = await _ratingPort.preview(
        subject: card.subject,
        expectedRevision: card.scheduleRevision,
        reviewedAt: _clock.now().toUtc(),
      );
      if (!_valid(generation) || state.current?.subject != card.subject) {
        _log(
          'preview.discarded card=${card.subject.subjectId} generation=$generation',
        );
        return;
      }
      _engine.setPreview(result);
      _log(
        'preview.success card=${card.subject.subjectId} revision=${result.revision}',
      );
      _notify();
    } catch (error) {
      if (!_valid(generation)) return;
      _log('preview.error card=${card.subject.subjectId} error=$error');
      _engine.setError(error);
      _notify();
    }
  }

  Future<void> submitRating(MemoryRating rating) async {
    final card = state.current;
    if (card == null || state.phase != ScheduledFlashcardPhase.answer) return;
    final preview = state.preview;
    if (preview == null) return;
    _engine.beginSubmitting(rating);
    _notify();
    final generation = _generation;
    final operationId = _pendingOperationId ??= _operationIdGenerator.newId();
    _log(
      'submit.start card=${card.subject.subjectId} rating=$rating revision=${card.scheduleRevision} operationId=$operationId generation=$generation',
    );
    try {
      await _ratingPort.submit(
        subject: card.subject,
        rating: rating,
        preview: _previewFor(preview, rating),
        expectedRevision: card.scheduleRevision,
        responseTime: _responseTime(),
        operationId: operationId,
      );
      if (!_valid(generation) || state.current?.subject != card.subject) {
        _log(
          'submit.discarded card=${card.subject.subjectId} operationId=$operationId',
        );
        return;
      }
      _pendingOperationId = null;
      _engine.advance();
      _log('submit.success card=${card.subject.subjectId}');
      _notify();
    } catch (error) {
      if (!_valid(generation)) return;
      if (error is MemoryScheduleConflictException) {
        _log(
          'submit.conflict card=${card.subject.subjectId} operationId=$operationId',
        );
        await _reloadAfterConflict(card, generation);
        return;
      }
      _engine.returnToAnswer(error);
      _log('submit.error card=${card.subject.subjectId} error=$error');
      _notify();
    }
  }

  /// 跳过当前卡片但不提交评分，用于"取消收藏"等业务动作完成后推进队列。
  void removeCurrent() {
    _generation++;
    _pendingOperationId = null;
    _log('remove_current card=${state.current?.subject.subjectId}');
    _engine.removeCurrent();
    _promptedAt = _clock.now().toUtc();
    _notify();
  }

  void dispose() {
    _log('dispose generation=$_generation');
    _disposed = true;
    _generation++;
    _listeners.clear();
  }

  Future<void> _reloadAfterConflict(
    ScheduledFlashcard<T> card,
    int generation,
  ) async {
    try {
      final revision = await _ratingPort.reloadRevision(card.subject);
      if (!_valid(generation) || state.current?.subject != card.subject) return;
      _pendingOperationId = null;
      _engine.replaceCurrentRevision(revision);
      _engine.returnToAnswer(
        const MemoryScheduleConflictException('评分已刷新，请重新确认。'),
      );
      _notify();
      await preview();
    } catch (error) {
      if (!_valid(generation)) return;
      _engine.returnToAnswer(error);
      _notify();
    }
  }

  Duration _responseTime() {
    final start = _promptedAt;
    if (start == null) return Duration.zero;
    final elapsed = _clock.now().toUtc().difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
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

  bool _valid(int generation) => !_disposed && generation == _generation;
  static void _ignoreLog(String message) {}
  void _log(String message) => _logger('[SCHEDULED_FLASHCARD] $message');
  void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

/// 将通用评分端口映射到 MemoryScheduler facade。
final class MemorySchedulerFlashcardRatingPort implements FlashcardRatingPort {
  const MemorySchedulerFlashcardRatingPort(this._scheduler);
  final MemoryScheduler _scheduler;

  @override
  Future<MemoryRatingPreviewSet> preview({
    required subject,
    required int expectedRevision,
    required DateTime reviewedAt,
  }) => _scheduler.previewRatings(
    PreviewMemoryRatingsQuery(
      subject: subject,
      expectedRevision: expectedRevision,
      reviewedAt: reviewedAt,
    ),
  );

  @override
  Future<MemoryReviewResult> submit({
    required subject,
    required MemoryRating rating,
    required MemoryRatingPreview preview,
    required int expectedRevision,
    required Duration responseTime,
    required String operationId,
  }) => _scheduler.review(
    ReviewMemoryCommand(
      subject: subject,
      rating: rating,
      preview: preview,
      expectedRevision: expectedRevision,
      reviewedAt: preview.reviewedAt,
      responseTime: responseTime,
      operationId: operationId,
    ),
  );

  @override
  Future<int> reloadRevision(subject) async {
    final schedule = await _scheduler.getSchedule(subject);
    if (schedule == null) {
      throw const MemoryScheduleNotFoundException('调度不存在。');
    }
    return schedule.revision;
  }
}
