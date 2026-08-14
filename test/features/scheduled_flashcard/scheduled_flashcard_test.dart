import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/features/memory_scheduler/domain/memory_profile.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_model_adapter.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_review_event.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_schedule.dart';
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

  test('engine enforces prompt, answer, follow-up and completion order', () {
    final engine = ScheduledFlashcardEngine<String, String>();
    engine.setDeck(<ScheduledFlashcard<String>>[card]);
    expect(engine.state.phase, ScheduledFlashcardPhase.prompt);

    engine.beginSubmitting(MemoryRating.good);
    expect(engine.state.phase, ScheduledFlashcardPhase.prompt);
    engine.revealAnswer();
    engine.beginSubmitting(MemoryRating.again);
    expect(engine.state.phase, ScheduledFlashcardPhase.submittingRating);
    engine.beginFollowUp('repeat');
    expect(engine.state.phase, ScheduledFlashcardPhase.followUp);
    engine.finishFollowUp(FollowUpOutcome.skipped);
    expect(engine.state.phase, ScheduledFlashcardPhase.completed);
    expect(engine.state.reviewedCount, 1);
  });

  test('empty deck completes immediately', () {
    final engine = ScheduledFlashcardEngine<String, String>();
    engine.setDeck(const <ScheduledFlashcard<String>>[]);
    expect(engine.state.phase, ScheduledFlashcardPhase.completed);
  });

  test(
    'controller submits with stable revision and follows up Again',
    () async {
      final port = _FakeRatingPort();
      final controller = ScheduledFlashcardController<String, String>(
        deckSource: _FakeDeckSource(<ScheduledFlashcard<String>>[card]),
        ratingPort: port,
        followUpPolicy: _FakeFollowUpPolicy(),
        operationIdGenerator: _FixedIds(),
      );
      await controller.load();
      controller.revealAnswer();
      await controller.preview();
      await controller.submitRating(MemoryRating.again);

      expect(port.lastRevision, 3);
      expect(port.lastOperationId, 'op-1');
      expect(controller.state.phase, ScheduledFlashcardPhase.followUp);
      controller.completeFollowUp();
      expect(controller.state.phase, ScheduledFlashcardPhase.completed);
      controller.dispose();
    },
  );

  test('late deck result is discarded after dispose', () async {
    final source = _CompletingDeckSource();
    final controller = ScheduledFlashcardController<String, String>(
      deckSource: source,
      ratingPort: _FakeRatingPort(),
      followUpPolicy: _FakeFollowUpPolicy(),
    );
    final load = controller.load();
    controller.dispose();
    source.complete(<ScheduledFlashcard<String>>[card]);
    await load;
    expect(controller.state.current, isNull);
  });
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

final class _FakeFollowUpPolicy
    implements FlashcardFollowUpPolicy<String, String> {
  @override
  String? followUpFor(String content, MemoryRating rating) =>
      rating == MemoryRating.again ? 'repeat $content' : null;
}

final class _FixedIds implements FlashcardOperationIdGenerator {
  @override
  String newId() => 'op-1';
}

final class _FakeRatingPort implements FlashcardRatingPort {
  int? lastRevision;
  String? lastOperationId;
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
