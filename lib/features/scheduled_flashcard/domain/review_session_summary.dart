/// 收藏复习会话完成时展示的本次统计快照。
library;

import '../../memory_scheduler/domain/memory_rating.dart';

/// 只记录本轮已成功持久化的评分，避免失败或取消收藏污染完成页数据。
final class ReviewSessionSummary {
  const ReviewSessionSummary({
    this.elapsed = Duration.zero,
    this.reviewedCount = 0,
    this.againCount = 0,
    this.goodCount = 0,
    this.easyCount = 0,
  });

  final Duration elapsed;
  final int reviewedCount;
  final int againCount;
  final int goodCount;
  final int easyCount;

  int get ratingCount => againCount + goodCount + easyCount;

  /// 保持率与全局复习统计保持一致：听懂了与轻松听懂视为成功保持。
  double get retentionRate =>
      ratingCount == 0 ? 0 : (goodCount + easyCount) / ratingCount;

  ReviewSessionSummary recordRating(MemoryRating rating) => switch (rating) {
    MemoryRating.again => ReviewSessionSummary(
      elapsed: elapsed,
      reviewedCount: reviewedCount,
      againCount: againCount + 1,
      goodCount: goodCount,
      easyCount: easyCount,
    ),
    MemoryRating.good => ReviewSessionSummary(
      elapsed: elapsed,
      reviewedCount: reviewedCount,
      againCount: againCount,
      goodCount: goodCount + 1,
      easyCount: easyCount,
    ),
    MemoryRating.easy => ReviewSessionSummary(
      elapsed: elapsed,
      reviewedCount: reviewedCount,
      againCount: againCount,
      goodCount: goodCount,
      easyCount: easyCount + 1,
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
    againCount: againCount,
    goodCount: goodCount,
    easyCount: easyCount,
  );
}
