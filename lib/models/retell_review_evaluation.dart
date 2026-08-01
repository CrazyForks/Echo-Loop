/// 复述 AI 评估的流式结果模型。
///
/// 字段与服务端 `POST /api/v1/stream/evaluate-review` 的 schema 一一对应：
/// `keyPoints[]` / `corrections[]` / `summary` / `rating` / `suggestion`。
/// `keyPoints[].keyPoint` 是用母语写的要点陈述（必填），`keyPoints[].original`
/// 才是原文摘录（原文语种、可为 null），两者不要混用。
/// 顶层 `transcript`（整段转录）不在 schema 内，由流的 `meta` 首帧改写成 `transcript`
/// 叶子后进入同一累积对象；它与 schema 内的 `keyPoints[].transcript`（要点摘录）
/// 是两个不同来源的字段，路径不同、不互相覆盖。
///
/// 流式协议是「按路径设叶子」的增量帧，任何字段都可能尚未到达，因此：
/// 枚举型字段一律可空（null = 未到达/无法识别），字符串型缺省为空串。
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
///
/// token 取值与服务端返回值一致；面向用户的友好文案由 UI 层映射。
enum RetellReviewRating { poor, fair, good, excellent, perfect }

/// null 表示评级尚未到达或无法识别，不做「最差评级」兜底，避免误导用户。
RetellReviewRating? _ratingValue(Object? value) => switch (value) {
  'poor' => RetellReviewRating.poor,
  'fair' => RetellReviewRating.fair,
  'good' => RetellReviewRating.good,
  'excellent' => RetellReviewRating.excellent,
  'perfect' => RetellReviewRating.perfect,
  _ => null,
};

/// 单条要点的还原状态。
///
/// 枚举顺序即 UI 统计条的固定展示顺序，不要按到达顺序重排。
enum RetellReviewKeyPointStatus {
  /// 表达正确。
  covered,

  /// 部分表达或明显不完整。
  partial,

  /// 完全没有表达。
  missed,

  /// 表达了但语义发生实质性偏差。
  distorted,

  /// 原文没有、学习者自己加进来的内容。
  added,
}

/// null 表示状态尚未到达或无法识别。
RetellReviewKeyPointStatus? _keyPointStatusValue(Object? value) =>
    switch (value) {
      'covered' => RetellReviewKeyPointStatus.covered,
      'partial' => RetellReviewKeyPointStatus.partial,
      'missed' => RetellReviewKeyPointStatus.missed,
      'distorted' => RetellReviewKeyPointStatus.distorted,
      'added' => RetellReviewKeyPointStatus.added,
      _ => null,
    };

/// 一条要点的还原情况。
///
/// 要点通常来自原文；`status == added` 时它是学习者自己加进来的内容。
///
/// [keyPoint] 是这条要点面向用户的完整表述（用户母语），也是 schema 里唯一必填的
/// 文本，因此被 UI 当作「该条已成形」的信号；[original] 与 [transcript] 只是分别
/// 在原文和转录里定位这条要点的摘录，语种各随其来源，摘不到就为空串。
class RetellReviewKeyPoint {
  /// 该要点用用户母语的完整表述，脱离摘录也能看懂。
  final String keyPoint;

  /// 原文中该要点出现处的逐字摘录，保持原文语种；`status == added` 时原文没有
  /// 对应内容，服务端返回 null，此处为空串。
  final String original;

  /// 学习者说到该要点的转录摘录，保持口语语种；无对应摘录时服务端返回 null，
  /// 此处为空串（`status == missed` 时必然为空）。
  final String transcript;

  /// 还原状态；null 表示流式过程中尚未到达。
  final RetellReviewKeyPointStatus? status;

  /// 针对该要点的反馈；无需说明时服务端返回 null，此处为空串。
  final String feedback;

  const RetellReviewKeyPoint({
    required this.keyPoint,
    required this.original,
    required this.transcript,
    required this.status,
    required this.feedback,
  });

  factory RetellReviewKeyPoint.fromJson(Map<String, dynamic> json) =>
      RetellReviewKeyPoint(
        keyPoint: _stringValue(json['keyPoint']),
        original: _stringValue(json['original']),
        transcript: _stringValue(json['transcript']),
        status: _keyPointStatusValue(json['status']),
        feedback: _stringValue(json['feedback']),
      );
}

/// 一条纠错的类别。
///
/// token 取值与服务端返回值一致；面向用户的标签与配色由 UI 层映射。
enum RetellReviewCorrectionType {
  /// 明确的语法结构错误。
  grammar,

  /// 用错的词、介词或搭配。
  wordChoice,

  /// 同义重复、空话、绕圈子。
  redundancy,

  /// 不算错但不地道的说法。
  phrasing,

  /// 缺少或用错连接词，逻辑关系不清。
  cohesion,
}

/// null 表示类别尚未到达或无法识别。
RetellReviewCorrectionType? _correctionTypeValue(Object? value) =>
    switch (value) {
      'grammar' => RetellReviewCorrectionType.grammar,
      'wordChoice' => RetellReviewCorrectionType.wordChoice,
      'redundancy' => RetellReviewCorrectionType.redundancy,
      'phrasing' => RetellReviewCorrectionType.phrasing,
      'cohesion' => RetellReviewCorrectionType.cohesion,
      _ => null,
    };

/// 一条有转录依据的局部表达纠错。
class RetellReviewCorrection {
  /// 纠错类别；null 表示流式过程中尚未到达。
  final RetellReviewCorrectionType? type;

  /// 转录中出问题的原始片段，保持口语语种。
  final String transcript;

  /// 自然的口语更正，保持口语语种。
  final String correction;

  /// 用用户母语给出的简短说明。
  final String explanation;

  const RetellReviewCorrection({
    required this.type,
    required this.transcript,
    required this.correction,
    required this.explanation,
  });

  factory RetellReviewCorrection.fromJson(Map<String, dynamic> json) =>
      RetellReviewCorrection(
        type: _correctionTypeValue(json['type']),
        transcript: _stringValue(json['transcript']),
        correction: _stringValue(json['correction']),
        explanation: _stringValue(json['explanation']),
      );
}

/// 一次复述评估的完整或流式半成品快照。
class RetellReviewEvaluation {
  /// 本次录音的转录文本，来自流的 `meta` 首帧。
  final String transcript;

  /// 总体评价。
  final String summary;

  /// 效果等级；null 表示尚未到达（schema 顺序上它是最后一个字段）。
  final RetellReviewRating? rating;

  /// 逐条要点还原情况，服务端上限 20 条；含学习者自己加进来的要点（`added`）。
  final List<RetellReviewKeyPoint> keyPoints;

  /// 唯一一条高价值建议；服务端可能返回 null，此处为空串。
  final String suggestion;

  /// 局部表达纠错，服务端上限 10 条；无问题时为空列表。
  final List<RetellReviewCorrection> corrections;

  const RetellReviewEvaluation({
    this.transcript = '',
    this.summary = '',
    this.rating,
    this.keyPoints = const [],
    this.suggestion = '',
    this.corrections = const [],
  });

  factory RetellReviewEvaluation.fromJson(Map<String, dynamic> json) =>
      RetellReviewEvaluation(
        transcript: _stringValue(json['transcript']),
        summary: _stringValue(json['summary']),
        rating: _ratingValue(json['rating']),
        keyPoints: _objectList(
          json['keyPoints'],
          RetellReviewKeyPoint.fromJson,
        ),
        suggestion: _stringValue(json['suggestion']),
        corrections: _objectList(
          json['corrections'],
          RetellReviewCorrection.fromJson,
        ),
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
