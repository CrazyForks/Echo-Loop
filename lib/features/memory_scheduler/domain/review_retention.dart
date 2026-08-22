/// 复习保持率的共享领域计算逻辑。
library;

import 'memory_rating.dart';

/// 一次与具体 UI 无关的评分事件。
final class ReviewRetentionEvent {
  const ReviewRetentionEvent({required this.subjectId, required this.rating});

  final String subjectId;
  final MemoryRating rating;
}

/// 按唯一条目的首次评分计算出的保持结果。
final class ReviewRetentionResult {
  const ReviewRetentionResult({
    required this.totalUniqueItems,
    required this.retainedUniqueItems,
    required this.againUniqueItems,
    required this.hardUniqueItems,
    required this.goodUniqueItems,
    required this.easyUniqueItems,
  });

  final int totalUniqueItems;
  final int retainedUniqueItems;
  final int againUniqueItems;
  final int hardUniqueItems;
  final int goodUniqueItems;
  final int easyUniqueItems;

  /// 保持率只看每个条目的首次评分，避免 Again 重试造成重复计权。
  double get retentionRate =>
      totalUniqueItems == 0 ? 0 : retainedUniqueItems / totalUniqueItems;
}

/// 复用本次复习和历史统计的唯一条目保持率算法。
final class ReviewRetentionCalculator {
  const ReviewRetentionCalculator._();

  /// 输入必须按评分发生顺序排列；每个条目只保留首次评分。
  static ReviewRetentionResult calculate(
    Iterable<ReviewRetentionEvent> events,
  ) {
    final firstRatings = <String, MemoryRating>{};
    for (final event in events) {
      firstRatings.putIfAbsent(event.subjectId, () => event.rating);
    }

    var again = 0;
    var hard = 0;
    var good = 0;
    var easy = 0;
    for (final rating in firstRatings.values) {
      switch (rating) {
        case MemoryRating.again:
          again++;
        case MemoryRating.hard:
          hard++;
        case MemoryRating.good:
          good++;
        case MemoryRating.easy:
          easy++;
      }
    }
    return ReviewRetentionResult(
      totalUniqueItems: firstRatings.length,
      retainedUniqueItems: good + easy,
      againUniqueItems: again,
      hardUniqueItems: hard,
      goodUniqueItems: good,
      easyUniqueItems: easy,
    );
  }
}
