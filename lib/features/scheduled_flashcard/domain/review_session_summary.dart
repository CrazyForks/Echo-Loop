/// 收藏复习会话完成时展示的本次统计快照。
library;

import '../../memory_scheduler/domain/memory_rating.dart';
import '../../memory_scheduler/domain/review_retention.dart';

/// 只记录本轮已成功持久化的评分，避免失败或取消收藏污染完成页数据。
final class ReviewSessionSummary {
  const ReviewSessionSummary({
    this.elapsed = Duration.zero,
    this.reviewedCount = 0,
    int againCount = 0,
    int goodCount = 0,
    int easyCount = 0,
    this.retentionEvents = const [],
  }) : _againClickCount = againCount,
       _goodClickCount = goodCount,
       _easyClickCount = easyCount;

  final Duration elapsed;
  final int reviewedCount;
  final int _againClickCount;
  final int _goodClickCount;
  final int _easyClickCount;
  final List<ReviewRetentionEvent> retentionEvents;

  ReviewRetentionResult get _retention =>
      ReviewRetentionCalculator.calculate(retentionEvents);

  /// 评分分布也按唯一条目的首次评分展示，而不是按重试点击次数展示。
  int get againCount => _retention.againUniqueItems;
  int get goodCount => _retention.goodUniqueItems;
  int get easyCount => _retention.easyUniqueItems;
  int get ratingCount => _retention.totalUniqueItems;

  /// 保持率与全局复习统计保持一致：按唯一条目的首次评分计算。
  double get retentionRate => _retention.retentionRate;

  ReviewSessionSummary recordRating({
    required String subjectId,
    required MemoryRating rating,
  }) => switch (rating) {
    MemoryRating.again => ReviewSessionSummary(
      elapsed: elapsed,
      reviewedCount: reviewedCount,
      againCount: _againClickCount + 1,
      goodCount: _goodClickCount,
      easyCount: _easyClickCount,
      retentionEvents: [
        ...retentionEvents,
        ReviewRetentionEvent(subjectId: subjectId, rating: rating),
      ],
    ),
    MemoryRating.good => ReviewSessionSummary(
      elapsed: elapsed,
      reviewedCount: reviewedCount,
      againCount: _againClickCount,
      goodCount: _goodClickCount + 1,
      easyCount: _easyClickCount,
      retentionEvents: [
        ...retentionEvents,
        ReviewRetentionEvent(subjectId: subjectId, rating: rating),
      ],
    ),
    MemoryRating.easy => ReviewSessionSummary(
      elapsed: elapsed,
      reviewedCount: reviewedCount,
      againCount: _againClickCount,
      goodCount: _goodClickCount,
      easyCount: _easyClickCount + 1,
      retentionEvents: [
        ...retentionEvents,
        ReviewRetentionEvent(subjectId: subjectId, rating: rating),
      ],
    ),
    MemoryRating.hard => throw ArgumentError.value(
      rating,
      'rating',
      '当前收藏复习不提供 hard 评分。',
    ),
  };

  ReviewSessionSummary complete({
    required Duration elapsed,
    required int reviewedCount,
  }) => ReviewSessionSummary(
    elapsed: elapsed,
    reviewedCount: reviewedCount,
    againCount: _againClickCount,
    goodCount: _goodClickCount,
    easyCount: _easyClickCount,
    retentionEvents: retentionEvents,
  );
}
