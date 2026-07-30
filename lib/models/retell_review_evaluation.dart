/// 复述 AI 评估的流式结果模型。
library;

String _stringValue(Object? value) => value is String ? value : '';

List<T> _objectList<T>(
  Object? value,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>) fromJson(item),
  ];
}

/// 服务端稳定的复述效果等级。
enum RetellReviewRating { keepGoing, fair, good, excellent, perfect }

RetellReviewRating _ratingValue(Object? value) => switch (value) {
  'fair' => RetellReviewRating.fair,
  'good' => RetellReviewRating.good,
  'excellent' => RetellReviewRating.excellent,
  'perfect' => RetellReviewRating.perfect,
  _ => RetellReviewRating.keepGoing,
};

/// 一条有证据支持的优点。
class RetellReviewStrength {
  final String point;
  final String evidence;

  const RetellReviewStrength({required this.point, required this.evidence});

  factory RetellReviewStrength.fromJson(Map<String, dynamic> json) =>
      RetellReviewStrength(
        point: _stringValue(json['point']),
        evidence: _stringValue(json['evidence']),
      );
}

/// 一条原文要点及学习者表达证据。
class RetellReviewCoveredKeyPoint {
  final String keyPoint;
  final String evidence;

  const RetellReviewCoveredKeyPoint({
    required this.keyPoint,
    required this.evidence,
  });

  factory RetellReviewCoveredKeyPoint.fromJson(Map<String, dynamic> json) =>
      RetellReviewCoveredKeyPoint(
        keyPoint: _stringValue(json['keyPoint']),
        evidence: _stringValue(json['evidence']),
      );
}

/// 一条遗漏或语义失真的原文要点。
class RetellReviewMissedKeyPoint {
  final String keyPoint;
  final String explanation;

  const RetellReviewMissedKeyPoint({
    required this.keyPoint,
    required this.explanation,
  });

  factory RetellReviewMissedKeyPoint.fromJson(Map<String, dynamic> json) =>
      RetellReviewMissedKeyPoint(
        keyPoint: _stringValue(json['keyPoint']),
        explanation: _stringValue(json['explanation']),
      );
}

/// 一条高价值的表达改进建议。
class RetellReviewImprovement {
  final String issue;
  final String evidence;
  final String suggestion;

  const RetellReviewImprovement({
    required this.issue,
    required this.evidence,
    required this.suggestion,
  });

  factory RetellReviewImprovement.fromJson(Map<String, dynamic> json) =>
      RetellReviewImprovement(
        issue: _stringValue(json['issue']),
        evidence: _stringValue(json['evidence']),
        suggestion: _stringValue(json['suggestion']),
      );
}

/// 一条明确的口语语法纠错。
class RetellReviewGrammarError {
  final String original;
  final String correction;
  final String explanation;

  const RetellReviewGrammarError({
    required this.original,
    required this.correction,
    required this.explanation,
  });

  factory RetellReviewGrammarError.fromJson(Map<String, dynamic> json) =>
      RetellReviewGrammarError(
        original: _stringValue(json['original']),
        correction: _stringValue(json['correction']),
        explanation: _stringValue(json['explanation']),
      );
}

/// 一次复述评估的完整或流式半成品快照。
class RetellReviewEvaluation {
  final String transcript;
  final String summary;
  final RetellReviewRating rating;
  final List<RetellReviewStrength> strengths;
  final List<RetellReviewCoveredKeyPoint> coveredKeyPoints;
  final List<RetellReviewMissedKeyPoint> missedKeyPoints;
  final List<RetellReviewImprovement> improvements;
  final List<RetellReviewGrammarError> grammarErrors;

  const RetellReviewEvaluation({
    this.transcript = '',
    this.summary = '',
    this.rating = RetellReviewRating.keepGoing,
    this.strengths = const [],
    this.coveredKeyPoints = const [],
    this.missedKeyPoints = const [],
    this.improvements = const [],
    this.grammarErrors = const [],
  });

  factory RetellReviewEvaluation.fromJson(Map<String, dynamic> json) =>
      RetellReviewEvaluation(
        transcript: _stringValue(json['transcript']),
        summary: _stringValue(json['summary']),
        rating: _ratingValue(json['rating']),
        strengths: _objectList(
          json['strengths'],
          RetellReviewStrength.fromJson,
        ),
        coveredKeyPoints: _objectList(
          json['coveredKeyPoints'],
          RetellReviewCoveredKeyPoint.fromJson,
        ),
        missedKeyPoints: _objectList(
          json['missedKeyPoints'],
          RetellReviewMissedKeyPoint.fromJson,
        ),
        improvements: _objectList(
          json['improvements'],
          RetellReviewImprovement.fromJson,
        ),
        grammarErrors: _objectList(
          json['grammarErrors'],
          RetellReviewGrammarError.fromJson,
        ),
      );

  RetellReviewEvaluation copyWith({String? transcript}) =>
      RetellReviewEvaluation(
        transcript: transcript ?? this.transcript,
        summary: summary,
        rating: rating,
        strengths: strengths,
        coveredKeyPoints: coveredKeyPoints,
        missedKeyPoints: missedKeyPoints,
        improvements: improvements,
        grammarErrors: grammarErrors,
      );
}

/// 评估流的一帧完整对象快照。
class RetellReviewStreamFrame {
  final RetellReviewEvaluation evaluation;
  final bool isFinal;

  const RetellReviewStreamFrame({
    required this.evaluation,
    required this.isFinal,
  });
}

/// 评估接口返回损坏或未正常结束时抛出的领域异常。
class RetellReviewStreamException implements Exception {
  const RetellReviewStreamException();
}
