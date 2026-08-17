import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/features/memory_scheduler/domain/memory_profile.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_model_adapter.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_review_event.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_schedule.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_scheduler_exceptions.dart';
import 'package:echo_loop/features/memory_scheduler/application/memory_scheduler.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_scheduler_results.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_subject_ref.dart';
import 'package:echo_loop/features/scheduled_flashcard/application/scheduled_flashcard_controller.dart';
import 'package:echo_loop/features/scheduled_flashcard/application/scheduled_flashcard_engine.dart';
import 'package:echo_loop/features/scheduled_flashcard/domain/scheduled_flashcard.dart';

void main() {
  final subject = MemorySubjectRef(namespace: 'test', subjectId: 'one');
  final card = ScheduledFlashcard<String>(
    subject: subject,
    content: 'hello',
    scheduleRevision: 3,
  );

  test('engine enforces prompt, answer, submitting and completion order', () {
    final engine = ScheduledFlashcardEngine<String>();
    engine.setDeck(<ScheduledFlashcard<String>>[card]);
    expect(engine.state.phase, ScheduledFlashcardPhase.prompt);

    engine.beginSubmitting(MemoryRating.good);
    expect(engine.state.phase, ScheduledFlashcardPhase.prompt);
    engine.revealAnswer();
    engine.beginSubmitting(MemoryRating.again);
    expect(engine.state.phase, ScheduledFlashcardPhase.submittingRating);
    engine.advance();
    expect(engine.state.phase, ScheduledFlashcardPhase.completed);
    expect(engine.state.reviewedCount, 1);
  });

  test('empty deck completes immediately', () {
    final engine = ScheduledFlashcardEngine<String>();
    engine.setDeck(const <ScheduledFlashcard<String>>[]);
    expect(engine.state.phase, ScheduledFlashcardPhase.completed);
  });

  group('removeCurrent', () {
    final second = ScheduledFlashcard<String>(
      subject: MemorySubjectRef(namespace: 'test', subjectId: 'two'),
      content: 'world',
      scheduleRevision: 1,
    );
    final third = ScheduledFlashcard<String>(
      subject: MemorySubjectRef(namespace: 'test', subjectId: 'three'),
      content: 'again',
      scheduleRevision: 1,
    );

    test('removing the middle card keeps index pointing at the next one', () {
      final engine = ScheduledFlashcardEngine<String>();
      engine.setDeck(<ScheduledFlashcard<String>>[card, second, third]);
      engine.removeCurrent();
      expect(engine.state.deck, <ScheduledFlashcard<String>>[second, third]);
      expect(engine.state.currentIndex, 0);
      expect(engine.state.current, second);
      expect(engine.state.phase, ScheduledFlashcardPhase.prompt);
      expect(engine.state.reviewedCount, 0);
    });

    test('removing the last card clamps the index', () {
      final engine = ScheduledFlashcardEngine<String>();
      engine.setDeck(<ScheduledFlashcard<String>>[card, second]);
      engine.advance();
      expect(engine.state.current, second);
      engine.removeCurrent();
      expect(engine.state.deck, <ScheduledFlashcard<String>>[card]);
      expect(engine.state.currentIndex, 0);
      expect(engine.state.current, card);
    });

    test('removing the only remaining card completes the session', () {
      final engine = ScheduledFlashcardEngine<String>();
      engine.setDeck(<ScheduledFlashcard<String>>[card]);
      engine.removeCurrent();
      expect(engine.state.deck, isEmpty);
      expect(engine.state.current, isNull);
      expect(engine.state.phase, ScheduledFlashcardPhase.completed);
    });

    test('controller bumps generation so stale preview is discarded', () async {
      final controller = ScheduledFlashcardController<String>(
        deckSource: _FakeDeckSource(<ScheduledFlashcard<String>>[card, second]),
        ratingPort: _FakeRatingPort(),
        operationIdGenerator: _FixedIds(),
      );
      await controller.load();
      controller.revealAnswer();
      final stalePreview = controller.preview();
      controller.removeCurrent();
      await stalePreview;
      expect(controller.state.current, second);
      expect(controller.state.preview, isNull);
    });
  });

  test('controller submits rating with stable idempotent revision', () async {
    final port = _FakeRatingPort();
    final controller = ScheduledFlashcardController<String>(
      deckSource: _FakeDeckSource(<ScheduledFlashcard<String>>[card]),
      ratingPort: port,
      operationIdGenerator: _FixedIds(),
    );
    await controller.load();
    controller.revealAnswer();
    await controller.preview();
    await controller.submitRating(MemoryRating.again);

    expect(port.lastRevision, 3);
    expect(port.lastOperationId, 'op-1');
    expect(controller.state.phase, ScheduledFlashcardPhase.completed);
    controller.dispose();
  });

  test('late deck result is discarded after dispose', () async {
    final source = _CompletingDeckSource();
    final controller = ScheduledFlashcardController<String>(
      deckSource: source,
      ratingPort: _FakeRatingPort(),
      operationIdGenerator: _FixedIds(),
    );
    final load = controller.load();
    controller.dispose();
    source.complete(<ScheduledFlashcard<String>>[card]);
    await load;
    expect(controller.state.current, isNull);
  });

  test('independent sessions use different operation IDs', () async {
    final ids = _SequenceIds(<String>['uuid-action-1', 'uuid-action-2']);
    final port = _FakeRatingPort();

    for (var index = 0; index < 2; index++) {
      final controller = ScheduledFlashcardController<String>(
        deckSource: _FakeDeckSource(<ScheduledFlashcard<String>>[card]),
        ratingPort: port,
        operationIdGenerator: ids,
      );
      await controller.load();
      controller.revealAnswer();
      await controller.preview();
      await controller.submitRating(MemoryRating.good);
      controller.dispose();
    }

    expect(port.operationIds, <String>['uuid-action-1', 'uuid-action-2']);
  });

  test(
    'operation ID rejection clears the pending ID for a new user action',
    () async {
      final port = _RejectOnceRatingPort();
      final controller = ScheduledFlashcardController<String>(
        deckSource: _FakeDeckSource(<ScheduledFlashcard<String>>[card]),
        ratingPort: port,
        operationIdGenerator: _SequenceIds(<String>[
          'legacy-conflict',
          'uuid-action-2',
        ]),
      );
      await controller.load();
      controller.revealAnswer();
      await controller.preview();

      await controller.submitRating(MemoryRating.good);
      expect(controller.state.phase, ScheduledFlashcardPhase.answer);
      await controller.submitRating(MemoryRating.good);

      expect(port.operationIds, <String>['legacy-conflict', 'uuid-action-2']);
      expect(controller.state.phase, ScheduledFlashcardPhase.completed);
    },
  );
}

final class _FakeDeckSource implements FlashcardDeckSource<String> {
  _FakeDeckSource(this.cards);
  final List<ScheduledFlashcard<String>> cards;
  @override
  Future<List<ScheduledFlashcard<String>>> load() async => cards;
}

final class _CompletingDeckSource implements FlashcardDeckSource<String> {
  final _completer = Completer<List<ScheduledFlashcard<String>>>();
  @override
  Future<List<ScheduledFlashcard<String>>> load() => _completer.future;
  void complete(List<ScheduledFlashcard<String>> cards) =>
      _completer.complete(cards);
}

final class _FixedIds implements MemoryIdGenerator {
  @override
  String newId() => 'op-1';
}

final class _SequenceIds implements MemoryIdGenerator {
  _SequenceIds(this._ids);
  final List<String> _ids;
  var _index = 0;

  @override
  String newId() => _ids[_index++];
}

class _FakeRatingPort implements FlashcardRatingPort {
  int? lastRevision;
  String? lastOperationId;
  final operationIds = <String>[];
  @override
  Future<MemoryRatingPreviewSet> preview({
    required MemorySubjectRef subject,
    required int expectedRevision,
    required DateTime reviewedAt,
  }) async {
    final state = MemoryModelState(
      version: 1,
      values: const <String, Object?>{},
    );
    MemoryRatingPreview item(MemoryRating rating) => MemoryRatingPreview(
      scheduleId: 'schedule',
      revision: expectedRevision,
      rating: rating,
      reviewedAt: reviewedAt,
      dueAt: reviewedAt,
      interval: Duration.zero,
      phase: MemorySchedulePhase.learning,
      transition: MemoryModelTransition(
        state: state,
        phase: MemorySchedulePhase.learning,
        dueAt: reviewedAt,
        lastReviewedAt: reviewedAt,
      ),
    );
    return MemoryRatingPreviewSet(
      scheduleId: 'schedule',
      revision: expectedRevision,
      reviewedAt: reviewedAt,
      again: item(MemoryRating.again),
      hard: item(MemoryRating.hard),
      good: item(MemoryRating.good),
      easy: item(MemoryRating.easy),
    );
  }

  @override
  Future<MemoryReviewResult> submit({
    required MemorySubjectRef subject,
    required MemoryRating rating,
    required MemoryRatingPreview preview,
    required int expectedRevision,
    required Duration responseTime,
    required String operationId,
  }) async {
    lastRevision = expectedRevision;
    lastOperationId = operationId;
    operationIds.add(operationId);
    final now = preview.reviewedAt;
    final profile = MemoryProfileRef(profileId: 'test', profileVersion: 1);
    final schedule = MemorySchedule(
      id: 'schedule',
      subject: subject,
      profile: profile,
      modelId: 'test',
      modelStateVersion: 1,
      phase: MemorySchedulePhase.learning,
      status: MemoryScheduleStatus.active,
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: now,
      dueAt: now,
      reviewCount: 1,
      lapseCount: rating == MemoryRating.again ? 1 : 0,
      revision: expectedRevision + 1,
      modelState: const <String, Object?>{},
      archivedAt: null,
    );
    final event = MemoryReviewEvent(
      id: 'event',
      scheduleId: schedule.id,
      sequence: 1,
      operationId: operationId,
      rating: rating,
      isLapse: rating == MemoryRating.again,
      reviewedAt: now,
      responseTime: responseTime,
      profile: profile,
      modelId: 'test',
      modelStateVersion: 1,
      dueBefore: now,
      dueAfter: now,
      scheduleRevisionAfter: expectedRevision + 1,
      createdAt: now,
    );
    return MemoryReviewResult(
      schedule: schedule,
      event: event,
      wasIdempotentReplay: false,
    );
  }

  @override
  Future<int> reloadRevision(MemorySubjectRef subject) async => 4;
}

final class _RejectOnceRatingPort extends _FakeRatingPort {
  var _shouldReject = true;

  @override
  Future<MemoryReviewResult> submit({
    required MemorySubjectRef subject,
    required MemoryRating rating,
    required MemoryRatingPreview preview,
    required int expectedRevision,
    required Duration responseTime,
    required String operationId,
  }) {
    if (_shouldReject) {
      _shouldReject = false;
      operationIds.add(operationId);
      return Future<MemoryReviewResult>.error(
        const MemoryOperationIdConflictException('legacy operation ID'),
      );
    }
    return super.submit(
      subject: subject,
      rating: rating,
      preview: preview,
      expectedRevision: expectedRevision,
      responseTime: responseTime,
      operationId: operationId,
    );
  }
}
