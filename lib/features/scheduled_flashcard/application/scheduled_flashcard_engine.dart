/// 调度 Flashcard 的纯 Dart 状态机。
library;

import '../../memory_scheduler/domain/memory_rating.dart';
import '../../memory_scheduler/domain/memory_scheduler_results.dart';
import '../domain/scheduled_flashcard.dart';

/// 状态机快照。
final class ScheduledFlashcardSessionState<T> {
  /// 创建状态。
  const ScheduledFlashcardSessionState({
    required this.deck,
    required this.currentIndex,
    required this.phase,
    required this.answerRevealed,
    required this.preview,
    required this.rating,
    required this.reviewedCount,
    this.error,
  });

  final List<ScheduledFlashcard<T>> deck;
  final int currentIndex;
  final ScheduledFlashcardPhase phase;
  final bool answerRevealed;
  final MemoryRatingPreviewSet? preview;
  final MemoryRating? rating;
  final int reviewedCount;
  final Object? error;

  ScheduledFlashcard<T>? get current =>
      currentIndex < deck.length ? deck[currentIndex] : null;
  int get total => deck.length;
  int get position => current == null ? deck.length : currentIndex + 1;
}

/// 不执行 IO 的卡片状态机。
final class ScheduledFlashcardEngine<T> {
  /// 创建空会话。
  ScheduledFlashcardEngine()
    : _state = ScheduledFlashcardSessionState<T>(
        deck: <ScheduledFlashcard<T>>[],
        currentIndex: 0,
        phase: ScheduledFlashcardPhase.loadingDeck,
        answerRevealed: false,
        preview: null,
        rating: null,
        reviewedCount: 0,
      );

  late ScheduledFlashcardSessionState<T> _state;
  ScheduledFlashcardSessionState<T> get state => _state;

  void setDeck(List<ScheduledFlashcard<T>> deck) {
    final snapshot = List<ScheduledFlashcard<T>>.unmodifiable(deck);
    _state = ScheduledFlashcardSessionState<T>(
      deck: snapshot,
      currentIndex: 0,
      phase: snapshot.isEmpty
          ? ScheduledFlashcardPhase.completed
          : ScheduledFlashcardPhase.prompt,
      answerRevealed: false,
      preview: null,
      rating: null,
      reviewedCount: 0,
    );
  }

  /// 从队列中移除当前卡片，不提交评分、不计入 reviewedCount。
  ///
  /// 用于"取消收藏"这类需要跳过当前卡但不产生评分事件的场景；移除后
  /// currentIndex 保持不变（自动指向原来的下一张），若移除的是最后一张则回退。
  void removeCurrent() {
    if (_state.currentIndex < 0 || _state.currentIndex >= _state.deck.length) {
      return;
    }
    final deck = List<ScheduledFlashcard<T>>.of(_state.deck)
      ..removeAt(_state.currentIndex);
    final nextIndex = deck.isEmpty
        ? 0
        : _state.currentIndex.clamp(0, deck.length - 1);
    _state = ScheduledFlashcardSessionState<T>(
      deck: List<ScheduledFlashcard<T>>.unmodifiable(deck),
      currentIndex: nextIndex,
      phase: deck.isEmpty
          ? ScheduledFlashcardPhase.completed
          : ScheduledFlashcardPhase.prompt,
      answerRevealed: false,
      preview: null,
      rating: null,
      reviewedCount: _state.reviewedCount,
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
    _state = ScheduledFlashcardSessionState<T>(
      deck: List<ScheduledFlashcard<T>>.unmodifiable(deck),
      currentIndex: _state.currentIndex,
      phase: _state.phase,
      answerRevealed: _state.answerRevealed,
      preview: _state.preview,
      rating: _state.rating,
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

  /// 评分提交成功后前进到下一张；已无跟读补练环节，评分即推进队列。
  void advance() {
    if (_state.current == null) return;
    final nextIndex = _state.currentIndex + 1;
    _state = ScheduledFlashcardSessionState<T>(
      deck: _state.deck,
      currentIndex: nextIndex,
      phase: nextIndex >= _state.deck.length
          ? ScheduledFlashcardPhase.completed
          : ScheduledFlashcardPhase.prompt,
      answerRevealed: false,
      preview: null,
      rating: null,
      reviewedCount: _state.reviewedCount + 1,
    );
  }

  ScheduledFlashcardSessionState<T> _copy({
    ScheduledFlashcardPhase? phase,
    bool? answerRevealed,
    MemoryRatingPreviewSet? preview,
    bool clearPreview = false,
    MemoryRating? rating,
    Object? error,
    bool clearError = false,
  }) {
    return ScheduledFlashcardSessionState<T>(
      deck: _state.deck,
      currentIndex: _state.currentIndex,
      phase: phase ?? _state.phase,
      answerRevealed: answerRevealed ?? _state.answerRevealed,
      preview: clearPreview ? null : preview ?? _state.preview,
      rating: rating ?? _state.rating,
      reviewedCount: _state.reviewedCount,
      error: clearError ? null : error ?? _state.error,
    );
  }
}
