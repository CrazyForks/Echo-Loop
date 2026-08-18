/// 收藏复习共用的调度设置。
library;

import 'package:collection/collection.dart';

/// 所有收藏类型共用的复习排序规则。
enum FavoriteReviewOrder { smart, dueAt, random }

/// 仅包含调度语义的设置；句子 AI 展示偏好保持在句子专属设置中。
class FavoriteReviewSettings {
  const FavoriteReviewSettings({
    this.showNextReviewTime = false,
    this.autoPlayFront = true,
    this.autoPlayBack = true,
    this.sentenceDailyReviewGoal,
    this.vocabularyDailyReviewGoal,
    this.order = FavoriteReviewOrder.smart,
  });

  final bool showNextReviewTime;

  /// 进入或切换到正面时是否自动播放当前卡片的音频。
  final bool autoPlayFront;

  /// 翻到背面时是否自动播放当前卡片对应的音频。
  final bool autoPlayBack;

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
    bool? autoPlayFront,
    bool? autoPlayBack,
    int? sentenceDailyReviewGoal,
    bool clearSentenceDailyReviewGoal = false,
    int? vocabularyDailyReviewGoal,
    bool clearVocabularyDailyReviewGoal = false,
    FavoriteReviewOrder? order,
  }) => FavoriteReviewSettings(
    showNextReviewTime: showNextReviewTime ?? this.showNextReviewTime,
    autoPlayFront: autoPlayFront ?? this.autoPlayFront,
    autoPlayBack: autoPlayBack ?? this.autoPlayBack,
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
    'autoPlayFront': autoPlayFront,
    'autoPlayBack': autoPlayBack,
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
      // 旧版正面固定自动播放；缺少新字段时保持这一默认体验。
      autoPlayFront: json['autoPlayFront'] is bool
          ? json['autoPlayFront'] == true
          : true,
      // 词汇旧字段只控制背面播放，迁移为所有收藏复习共用的背面偏好。
      autoPlayBack: json['autoPlayBack'] is bool
          ? json['autoPlayBack'] == true
          : json['autoPlayVocabularySourceSentence'] is bool
          ? json['autoPlayVocabularySourceSentence'] == true
          : true,
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
