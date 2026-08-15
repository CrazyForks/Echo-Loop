import 'package:echo_loop/models/favorite_review_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('旧单一每日目标迁移为句子目标，词汇目标默认不限', () {
    final settings = FavoriteReviewSettings.fromJson({'dailyReviewGoal': 20});

    expect(settings.sentenceDailyReviewGoal, 20);
    expect(settings.vocabularyDailyReviewGoal, isNull);
  });

  test('两个独立目标都能序列化和恢复', () {
    const settings = FavoriteReviewSettings(
      sentenceDailyReviewGoal: 10,
      vocabularyDailyReviewGoal: 30,
    );

    expect(
      FavoriteReviewSettings.fromJson(settings.toJson()).toJson(),
      settings.toJson(),
    );
  });
}
