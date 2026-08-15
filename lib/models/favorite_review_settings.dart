/// 收藏复习共用的调度设置。
library;

import 'package:collection/collection.dart';

/// 所有收藏类型共用的复习排序规则。
enum FavoriteReviewOrder { smart, dueAt, random }

/// 仅包含调度语义的设置；句子 AI 展示偏好保持在句子专属设置中。
class FavoriteReviewSettings {
  const FavoriteReviewSettings({
    this.showNextReviewTime = false,
    this.sentenceDailyReviewGoal,
    this.vocabularyDailyReviewGoal,
    this.order = FavoriteReviewOrder.smart,
  });

  final bool showNextReviewTime;

  /// 收藏句的每日复习目标；为空时不限制。
  final int? sentenceDailyReviewGoal;

  /// 收藏词汇（单词与意群共用）的每日复习目标；为空时不限制。
  final int? vocabularyDailyReviewGoal;
  final FavoriteReviewOrder order;

  static const dailyReviewGoalOptions = <int?>[
    null,
    5,
    10,
    15,
    20,
    30,
    40,
    50,
    60,
    70,
    80,
    90,
    100,
  ];

  FavoriteReviewSettings copyWith({
    bool? showNextReviewTime,
    int? sentenceDailyReviewGoal,
    bool clearSentenceDailyReviewGoal = false,
    int? vocabularyDailyReviewGoal,
    bool clearVocabularyDailyReviewGoal = false,
    FavoriteReviewOrder? order,
  }) => FavoriteReviewSettings(
    showNextReviewTime: showNextReviewTime ?? this.showNextReviewTime,
    sentenceDailyReviewGoal: clearSentenceDailyReviewGoal
        ? null
        : sentenceDailyReviewGoal ?? this.sentenceDailyReviewGoal,
    vocabularyDailyReviewGoal: clearVocabularyDailyReviewGoal
        ? null
        : vocabularyDailyReviewGoal ?? this.vocabularyDailyReviewGoal,
    order: order ?? this.order,
  );

  Map<String, dynamic> toJson() => {
    'showNextReviewTime': showNextReviewTime,
    'sentenceDailyReviewGoal': sentenceDailyReviewGoal,
    'vocabularyDailyReviewGoal': vocabularyDailyReviewGoal,
    'order': order.name,
  };

  factory FavoriteReviewSettings.fromJson(Map<String, dynamic> json) {
    // 旧版的单一目标只服务于收藏句，升级后保持该语义。
    final rawSentenceGoal =
        json['sentenceDailyReviewGoal'] ?? json['dailyReviewGoal'];
    final rawVocabularyGoal = json['vocabularyDailyReviewGoal'];
    final rawOrder = json['order'];
    return FavoriteReviewSettings(
      showNextReviewTime: json['showNextReviewTime'] is bool
          ? json['showNextReviewTime'] == true
          : false,
      sentenceDailyReviewGoal:
          rawSentenceGoal is int &&
              dailyReviewGoalOptions.contains(rawSentenceGoal)
          ? rawSentenceGoal
          : null,
      vocabularyDailyReviewGoal:
          rawVocabularyGoal is int &&
              dailyReviewGoalOptions.contains(rawVocabularyGoal)
          ? rawVocabularyGoal
          : null,
      order: rawOrder is String
          ? FavoriteReviewOrder.values.firstWhereOrNull(
                  (item) => item.name == rawOrder,
                ) ??
                FavoriteReviewOrder.smart
          : FavoriteReviewOrder.smart,
    );
  }
}
