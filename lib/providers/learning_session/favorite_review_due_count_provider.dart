/// 收藏复习入口使用的实际待复习数量。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/memory_scheduler/domain/memory_namespaces.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../features/memory_scheduler/providers/memory_scheduler_providers.dart';

/// 统一使两个收藏复习入口的到期数量失效。
///
/// StatefulShell 会保留收藏页实例；从其它主 Tab、统计页或回收站返回时必须
/// 显式刷新，不能依赖 widget 重建。
void refreshFavoriteReviewDueCounts(WidgetRef ref) {
  ref.invalidate(favoriteSentenceDueCountProvider);
  ref.invalidate(favoriteVocabularyDueCountProvider);
}

/// 当前收藏句子在调度器和每日目标限制下实际可进入复习的数量。
final favoriteSentenceDueCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  return ref
      .watch(memorySchedulerProvider)
      .getDueCount(
        DueMemoryCountQuery(
          namespaces: {kSavedSentenceNamespace},
          phases: null,
          dueBeforeOrAt: DateTime.now(),
        ),
      );
});

/// 当前收藏词汇（单词 + 意群）实际可进入复习的数量。
final favoriteVocabularyDueCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  return ref
      .watch(memorySchedulerProvider)
      .getDueCount(
        DueMemoryCountQuery(
          namespaces: kSavedWordAndSenseGroupNamespaces.toSet(),
          phases: null,
          dueBeforeOrAt: DateTime.now(),
        ),
      );
});
