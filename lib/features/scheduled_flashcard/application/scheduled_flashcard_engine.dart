/// 调度 Flashcard 的纯 Dart 状态机。
library;

import '../../memory_scheduler/domain/memory_rating.dart';
import '../../memory_scheduler/domain/memory_scheduler_results.dart';
import '../domain/scheduled_flashcard.dart';

/// 状态机快照。
final class ScheduledFlashcardSessionState<T, F> {
  /// 创建状态。
  const ScheduledFlashcardSessionState({
    required this.deck,
    required this.currentIndex,
    required this.phase,
    required this.answerRevealed,
    required this.preview,
    required this.rating,
    required this.followUp,
    required this.followUpOutcome,
    required this.reviewedCount,
    this.error,
  });

  final List<ScheduledFlashcard<T>> deck;
  final int currentIndex;
  final ScheduledFlashcardPhase phase;
  final bool answerRevealed;
  final MemoryRatingPreviewSet? preview;
  final MemoryRating? rating;
  final F? followUp;
  final FollowUpOutcome? followUpOutcome;
  final int reviewedCount;
  final Object? error;

  ScheduledFlashcard<T>? get current =>
      currentIndex < deck.length ? deck[currentIndex] : null;
  int get total => deck.length;
  int get position => current == null ? deck.length : currentIndex + 1;
}

/// 不执行 IO 的卡片状态机。
final class ScheduledFlashcardEngine<T, F> {
  /// 创建空会话。
  ScheduledFlashcardEngine()
    : _state = ScheduledFlashcardSessionState<T, F>(
        deck: <ScheduledFlashcard<T>>[],
        currentIndex: 0,
        phase: ScheduledFlashcardPhase.loadingDeck,
        answerRevealed: false,
        preview: null,
        rating: null,
        followUp: null,
        followUpOutcome: null,
        reviewedCount: 0,
      );

  late ScheduledFlashcardSessionState<T, F> _state;
  ScheduledFlashcardSessionState<T, F> get state => _state;

  void setDeck(List<ScheduledFlashcard<T>> deck) {
    final snapshot = List<ScheduledFlashcard<T>>.unmodifiable(deck);
    _state = ScheduledFlashcardSessionState<T, F>(
      deck: snapshot,
      currentIndex: 0,
      phase: snapshot.isEmpty
          ? ScheduledFlashcardPhase.completed
          : ScheduledFlashcardPhase.prompt,
      answerRevealed: false,
      preview: null,
      rating: null,
      followUp: null,
      followUpOutcome: null,
      reviewedCount: 0,
    );
  }

  void revealAnswer() {
    if (_state.phase != ScheduledFlashcardPhase.prompt) return;
    _state = _copy(phase: ScheduledFlashcardPhase.answer, answerRevealed: true);
  }

  void setPreview(MemoryRatingPreviewSet preview) {
    if (_state.phase != ScheduledFlashcardPhase.answer) return;
    _state = _copy(preview: preview, clearError: true);
  }

  void setError(Object error) => _state = _copy(error: error);

  /// 用服务端最新 revision 替换当前快照，保留会话内队列顺序。
  void replaceCurrentRevision(int revision) {
    final current = _state.current;
    if (current == null) return;
    final deck = List<ScheduledFlashcard<T>>.of(_state.deck);
    deck[_state.currentIndex] = ScheduledFlashcard<T>(
      subject: current.subject,
      content: current.content,
      scheduleRevision: revision,
    );
    _state = ScheduledFlashcardSessionState<T, F>(
      deck: List<ScheduledFlashcard<T>>.unmodifiable(deck),
      currentIndex: _state.currentIndex,
      phase: _state.phase,
      answerRevealed: _state.answerRevealed,
      preview: _state.preview,
      rating: _state.rating,
      followUp: _state.followUp,
      followUpOutcome: _state.followUpOutcome,
      reviewedCount: _state.reviewedCount,
      error: _state.error,
    );
  }

  void beginSubmitting(MemoryRating rating) {
    if (!_state.answerRevealed ||
        _state.phase != ScheduledFlashcardPhase.answer) {
      return;
    }
    _state = _copy(
      phase: ScheduledFlashcardPhase.submittingRating,
      rating: rating,
      clearError: true,
    );
  }

  /// 提交失败时回到可重试的答案面。
  void returnToAnswer(Object error) {
    _state = _copy(
      phase: ScheduledFlashcardPhase.answer,
      answerRevealed: true,
      error: error,
    );
  }

  void beginFollowUp(F? followUp) {
    if (followUp == null) {
      advance();
      return;
    }
    _state = _copy(
      phase: ScheduledFlashcardPhase.followUp,
      followUp: followUp,
      setFollowUp: true,
      followUpOutcome: null,
      setFollowUpOutcome: true,
    );
  }

  void finishFollowUp(FollowUpOutcome outcome) {
    if (_state.phase != ScheduledFlashcardPhase.followUp) return;
    _state = _copy(followUpOutcome: outcome, setFollowUpOutcome: true);
    advance();
  }

  void advance() {
    if (_state.current == null) return;
    final nextIndex = _state.currentIndex + 1;
    _state = ScheduledFlashcardSessionState<T, F>(
      deck: _state.deck,
      currentIndex: nextIndex,
      phase: nextIndex >= _state.deck.length
          ? ScheduledFlashcardPhase.completed
          : ScheduledFlashcardPhase.prompt,
      answerRevealed: false,
      preview: null,
      rating: null,
      followUp: null,
      followUpOutcome: null,
      reviewedCount: _state.reviewedCount + 1,
    );
  }

  ScheduledFlashcardSessionState<T, F> _copy({
    ScheduledFlashcardPhase? phase,
    bool? answerRevealed,
    MemoryRatingPreviewSet? preview,
    bool clearPreview = false,
    MemoryRating? rating,
    F? followUp,
    bool setFollowUp = false,
    FollowUpOutcome? followUpOutcome,
    bool setFollowUpOutcome = false,
    Object? error,
    bool clearError = false,
  }) {
    return ScheduledFlashcardSessionState<T, F>(
      deck: _state.deck,
      currentIndex: _state.currentIndex,
      phase: phase ?? _state.phase,
      answerRevealed: answerRevealed ?? _state.answerRevealed,
      preview: clearPreview ? null : preview ?? _state.preview,
      rating: rating ?? _state.rating,
      followUp: setFollowUp ? followUp : _state.followUp,
      followUpOutcome: setFollowUpOutcome
          ? followUpOutcome
          : _state.followUpOutcome,
      reviewedCount: _state.reviewedCount,
      error: clearError ? null : error ?? _state.error,
    );
  }
}
