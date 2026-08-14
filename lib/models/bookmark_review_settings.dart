/// 收藏句 FSRS 复习设置。
library;

import 'package:collection/collection.dart';

enum BookmarkReviewOrder { smart, dueAt, random }

class BookmarkReviewSettings {
  const BookmarkReviewSettings({
    this.showNextReviewTime = false,
    this.dailyReviewGoal,
    this.order = BookmarkReviewOrder.smart,
    this.autoShowAiExplanation = true,
    this.autoShowAiAnalysis = false,
    this.autoShowAiTranslation = true,
    this.autoShowAiSenseGroups = false,
  });

  final bool showNextReviewTime;
  final int? dailyReviewGoal;
  final BookmarkReviewOrder order;
  final bool autoShowAiExplanation;
  final bool autoShowAiAnalysis;
  final bool autoShowAiTranslation;
  final bool autoShowAiSenseGroups;

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

  BookmarkReviewSettings copyWith({
    bool? showNextReviewTime,
    int? dailyReviewGoal,
    bool clearDailyReviewGoal = false,
    BookmarkReviewOrder? order,
    bool? autoShowAiExplanation,
    bool? autoShowAiAnalysis,
    bool? autoShowAiTranslation,
    bool? autoShowAiSenseGroups,
  }) => BookmarkReviewSettings(
    showNextReviewTime: showNextReviewTime ?? this.showNextReviewTime,
    dailyReviewGoal: clearDailyReviewGoal
        ? null
        : dailyReviewGoal ?? this.dailyReviewGoal,
    order: order ?? this.order,
    autoShowAiExplanation: autoShowAiExplanation ?? this.autoShowAiExplanation,
    autoShowAiAnalysis: autoShowAiAnalysis ?? this.autoShowAiAnalysis,
    autoShowAiTranslation: autoShowAiTranslation ?? this.autoShowAiTranslation,
    autoShowAiSenseGroups: autoShowAiSenseGroups ?? this.autoShowAiSenseGroups,
  );

  Map<String, dynamic> toJson() => {
    'showNextReviewTime': showNextReviewTime,
    'dailyReviewGoal': dailyReviewGoal,
    'order': order.name,
    'autoShowAiExplanation': autoShowAiExplanation,
    'autoShowAiAnalysis': autoShowAiAnalysis,
    'autoShowAiTranslation': autoShowAiTranslation,
    'autoShowAiSenseGroups': autoShowAiSenseGroups,
  };

  factory BookmarkReviewSettings.fromJson(Map<String, dynamic> json) {
    final rawGoal = json['dailyReviewGoal'];
    final goal = rawGoal == null || rawGoal is! int
        ? null
        : dailyReviewGoalOptions.contains(rawGoal)
        ? rawGoal
        : null;
    final rawOrder = json['order'];
    final order = rawOrder is String
        ? BookmarkReviewOrder.values
                  .where((item) => item.name == rawOrder)
                  .firstOrNull ??
              BookmarkReviewOrder.smart
        : BookmarkReviewOrder.smart;
    return BookmarkReviewSettings(
      showNextReviewTime: json['showNextReviewTime'] is bool
          ? json['showNextReviewTime'] as bool
          : false,
      dailyReviewGoal: goal,
      order: order,
      autoShowAiExplanation: json['autoShowAiExplanation'] is bool
          ? json['autoShowAiExplanation'] == true
          : true,
      autoShowAiAnalysis: json['autoShowAiAnalysis'] is bool
          ? json['autoShowAiAnalysis'] == true
          : false,
      autoShowAiTranslation: json['autoShowAiTranslation'] is bool
          ? json['autoShowAiTranslation'] == true
          : true,
      autoShowAiSenseGroups: json['autoShowAiSenseGroups'] is bool
          ? json['autoShowAiSenseGroups'] == true
          : false,
    );
  }
}
