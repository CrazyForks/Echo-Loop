/// 收藏复习入口使用的实际待复习数量。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/providers.dart';

import '../favorite_review_settings_provider.dart';
import '../saved_sense_group_provider.dart';
import '../saved_word_provider.dart';
import 'favorite_sentence_deck_source.dart';
import 'favorite_vocabulary_deck_source.dart';
import '../../features/memory_scheduler/providers/memory_scheduler_providers.dart';

/// 当前收藏句子在调度器和每日目标限制下实际可进入复习的数量。
final favoriteSentenceDueCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final bookmarks = await ref.watch(bookmarkListProvider.future);
  final source = FavoriteSentenceDeckSource(
    bookmarks: bookmarks,
    scheduler: ref.watch(memorySchedulerProvider),
    settings: ref.watch(favoriteReviewSettingsProvider),
  );
  return (await source.load()).length;
});

/// 当前收藏词汇（单词 + 意群）实际可进入复习的数量。
final favoriteVocabularyDueCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final words = await ref.watch(savedWordListProvider.future);
  final phrases = await ref.watch(savedSenseGroupListProvider.future);
  final source = FavoriteVocabularyDeckSource(
    words: words,
    phrases: phrases,
    scheduler: ref.watch(memorySchedulerProvider),
    settings: ref.watch(favoriteReviewSettingsProvider),
  );
  return (await source.load()).length;
});
