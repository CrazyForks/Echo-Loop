import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../database/providers.dart';
import 'review_statistics_repository.dart';

part 'review_statistics_provider.g.dart';

@riverpod
class ReviewStatisticsNotifier extends _$ReviewStatisticsNotifier {
  ReviewStatisticsScope _scope = ReviewStatisticsScope.all;

  @override
  Future<ReviewStatistics> build() => _load();

  ReviewStatisticsScope get scope => _scope;

  Future<ReviewStatistics> _load() => ReviewStatisticsRepository(
    ref.read(appDatabaseProvider),
  ).load(now: DateTime.now(), scope: _scope);

  Future<void> setScope(ReviewStatisticsScope scope) async {
    if (_scope == scope) return;
    _scope = scope;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(_load);
    state = result;
  }
}
