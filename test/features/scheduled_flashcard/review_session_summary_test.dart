import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:echo_loop/features/scheduled_flashcard/domain/review_session_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tracks successful ratings and computes retention from good and easy',
    () {
      final summary = const ReviewSessionSummary()
          .recordRating(MemoryRating.again)
          .recordRating(MemoryRating.good)
          .recordRating(MemoryRating.easy)
          .complete(
            elapsed: const Duration(minutes: 2, seconds: 8),
            reviewedCount: 2,
          );

      expect(summary.againCount, 1);
      expect(summary.goodCount, 1);
      expect(summary.easyCount, 1);
      expect(summary.ratingCount, 3);
      expect(summary.reviewedCount, 2);
      expect(summary.elapsed, const Duration(minutes: 2, seconds: 8));
      expect(summary.retentionRate, closeTo(2 / 3, 0.0001));
    },
  );
}
