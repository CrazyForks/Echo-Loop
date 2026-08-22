import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/features/review_statistics/review_statistics_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('空数据库返回稳定的零值趋势', () async {
    final now = DateTime(2026, 8, 22, 10);
    final stats = await ReviewStatisticsRepository(db).load(now: now);

    expect(stats.todayReviewedCards, 0);
    expect(stats.todaySeconds, 0);
    expect(stats.dueNow, 0);
    expect(stats.streak, 0);
    expect(stats.retentionRate, 0);
    expect(stats.dailyTrend, hasLength(30));
    expect(stats.upcomingDue, hasLength(7));
    expect(stats.dailyTrend.every((day) => day.reviewedCards == 0), isTrue);
  });
}
