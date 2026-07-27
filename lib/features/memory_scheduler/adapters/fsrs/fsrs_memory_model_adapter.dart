/// `fsrs` 包的记忆调度 adapter；第三方算法类型只允许出现在此目录。
library;

import 'package:fsrs/fsrs.dart' as fsrs;

import '../../domain/memory_model_adapter.dart';
import '../../domain/memory_profile.dart';
import '../../domain/memory_rating.dart';
import '../../domain/memory_schedule.dart';
import '../../domain/memory_scheduler_exceptions.dart';
import 'fsrs_state_codec.dart';

/// 以冻结 Profile 驱动 FSRS 2.0.1 的应用 adapter。
final class FsrsMemoryModelAdapter implements MemoryModelAdapter {
  /// 创建 FSRS adapter。
  FsrsMemoryModelAdapter({FsrsStateCodec? stateCodec})
    : _stateCodec = stateCodec ?? FsrsStateCodec();

  final FsrsStateCodec _stateCodec;

  @override
  String get modelId => 'fsrs';

  @override
  Set<int> get supportedStateVersions => const <int>{kFsrsStateVersion};

  @override
  void validateProfile(MemoryProfile profile) {
    if (profile.modelId != modelId) {
      throw MemoryValidationException('FSRS adapter 不支持模型: ${profile.modelId}');
    }
    _schedulerFor(profile);
  }

  @override
  MemoryModelState createInitialState({
    required MemoryProfile profile,
    required DateTime createdAt,
  }) {
    validateProfile(profile);
    final utcCreatedAt = createdAt.toUtc();
    final card = fsrs.Card(
      cardId: 0,
      state: fsrs.State.learning,
      step: 0,
      stability: null,
      difficulty: null,
      due: utcCreatedAt,
      lastReview: null,
    );
    return _stateCodec.encode(card);
  }

  @override
  MemoryModelPreviewSet preview({
    required MemoryProfile profile,
    required MemoryModelState current,
    required DateTime reviewedAt,
  }) {
    final scheduler = _schedulerFor(profile);
    final card = _stateCodec.decode(current);
    final utcReviewedAt = reviewedAt.toUtc();
    return MemoryModelPreviewSet(
      again: _preview(scheduler, card, fsrs.Rating.again, utcReviewedAt),
      hard: _preview(scheduler, card, fsrs.Rating.hard, utcReviewedAt),
      good: _preview(scheduler, card, fsrs.Rating.good, utcReviewedAt),
      easy: _preview(scheduler, card, fsrs.Rating.easy, utcReviewedAt),
    );
  }

  @override
  MemoryModelTransition review({
    required MemoryProfile profile,
    required MemoryModelState current,
    required MemoryRating rating,
    required DateTime reviewedAt,
  }) {
    final scheduler = _schedulerFor(profile);
    final result = scheduler.reviewCard(
      _stateCodec.decode(current),
      _rating(rating),
      reviewDateTime: reviewedAt.toUtc(),
    );
    return _transition(result.card);
  }

  MemoryModelPreview _preview(
    fsrs.Scheduler scheduler,
    fsrs.Card card,
    fsrs.Rating rating,
    DateTime reviewedAt,
  ) {
    final result = scheduler.reviewCard(
      card,
      rating,
      reviewDateTime: reviewedAt,
    );
    final transition = _transition(result.card);
    return MemoryModelPreview(
      state: transition.state,
      phase: transition.phase,
      dueAt: transition.dueAt,
      lastReviewedAt: transition.lastReviewedAt,
    );
  }

  MemoryModelTransition _transition(fsrs.Card card) {
    final lastReviewedAt = card.lastReview;
    if (lastReviewedAt == null) {
      throw MemoryModelStateCorruptedException('FSRS 评分后缺少 lastReview。');
    }
    return MemoryModelTransition(
      state: _stateCodec.encode(card),
      phase: _phase(card.state),
      dueAt: card.due,
      lastReviewedAt: lastReviewedAt,
    );
  }

  fsrs.Scheduler _schedulerFor(MemoryProfile profile) {
    final parameters = profile.parameters;
    const expectedKeys = <String>{
      'weights',
      'desiredRetention',
      'learningStepsSeconds',
      'relearningStepsSeconds',
      'maximumIntervalDays',
    };
    if (parameters.keys.toSet().length != expectedKeys.length ||
        !parameters.keys.toSet().containsAll(expectedKeys)) {
      throw MemoryValidationException('FSRS Profile 参数键必须精确匹配冻结配置。');
    }
    final weights = _doubleList(parameters['weights'], 'weights');
    if (weights.length != 21) {
      throw MemoryValidationException('FSRS weights 必须恰好包含 21 个数值。');
    }
    final desiredRetention = _finiteDouble(
      parameters['desiredRetention'],
      'desiredRetention',
    );
    if (desiredRetention <= 0 || desiredRetention >= 1) {
      throw MemoryValidationException('FSRS desiredRetention 必须在 0 与 1 之间。');
    }
    final maximumInterval = _positiveInt(
      parameters['maximumIntervalDays'],
      'maximumIntervalDays',
    );
    final learningSteps = _durations(
      parameters['learningStepsSeconds'],
      'learningStepsSeconds',
    );
    final relearningSteps = _durations(
      parameters['relearningStepsSeconds'],
      'relearningStepsSeconds',
    );
    try {
      return fsrs.Scheduler(
        parameters: weights,
        desiredRetention: desiredRetention,
        learningSteps: learningSteps,
        relearningSteps: relearningSteps,
        maximumInterval: maximumInterval,
        enableFuzzing: profile.enableFuzzing,
      );
    } on ArgumentError catch (error) {
      throw MemoryValidationException('FSRS Profile 参数越界: ${error.message}');
    }
  }
}

fsrs.Rating _rating(MemoryRating rating) => switch (rating) {
  MemoryRating.again => fsrs.Rating.again,
  MemoryRating.hard => fsrs.Rating.hard,
  MemoryRating.good => fsrs.Rating.good,
  MemoryRating.easy => fsrs.Rating.easy,
};

MemorySchedulePhase _phase(fsrs.State state) => switch (state) {
  fsrs.State.learning => MemorySchedulePhase.learning,
  fsrs.State.review => MemorySchedulePhase.review,
  fsrs.State.relearning => MemorySchedulePhase.relearning,
};

double _finiteDouble(Object? value, String key) {
  if (value is num && value.isFinite) return value.toDouble();
  throw MemoryValidationException('FSRS $key 必须是有限数值。');
}

int _positiveInt(Object? value, String key) {
  if (value is int && value > 0) return value;
  throw MemoryValidationException('FSRS $key 必须是大于 0 的 int。');
}

List<double> _doubleList(Object? value, String key) {
  if (value is! Iterable<Object?>) {
    throw MemoryValidationException('FSRS $key 必须是数值列表。');
  }
  return List<double>.unmodifiable(
    value.map((element) => _finiteDouble(element, key)),
  );
}

List<Duration> _durations(Object? value, String key) {
  if (value is! Iterable<Object?>) {
    throw MemoryValidationException('FSRS $key 必须是秒数列表。');
  }
  final result = value
      .map((element) => Duration(seconds: _positiveInt(element, key)))
      .toList(growable: false);
  if (result.isEmpty) {
    throw MemoryValidationException('FSRS $key 不得为空。');
  }
  return result;
}
