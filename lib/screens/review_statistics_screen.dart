import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/review_statistics/review_statistics_provider.dart';
import '../features/review_statistics/review_statistics_repository.dart';
import '../l10n/app_localizations.dart';

/// 收藏复习统计页。
class ReviewStatisticsScreen extends ConsumerWidget {
  const ReviewStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reviewStatisticsNotifierProvider);
    final notifier = ref.read(reviewStatisticsNotifierProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewStatisticsTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(l10n.reviewStatisticsLoadError)),
        data: (stats) => RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<ReviewStatisticsScope>(
                segments: [
                  ButtonSegment(
                    value: ReviewStatisticsScope.all,
                    label: Text(l10n.reviewStatisticsAll),
                  ),
                  ButtonSegment(
                    value: ReviewStatisticsScope.sentences,
                    label: Text(l10n.reviewStatisticsSentences),
                  ),
                  ButtonSegment(
                    value: ReviewStatisticsScope.vocabulary,
                    label: Text(l10n.reviewStatisticsVocabulary),
                  ),
                ],
                selected: {notifier.scope},
                onSelectionChanged: (value) => notifier.setScope(value.first),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.65,
                children: [
                  _MetricCard(
                    l10n.reviewStatisticsTodayReviewed,
                    '${stats.todayReviewedCards}',
                    Icons.style_outlined,
                  ),
                  _MetricCard(
                    l10n.reviewStatisticsDuration,
                    _formatDuration(stats.todaySeconds),
                    Icons.timer_outlined,
                  ),
                  _MetricCard(
                    l10n.reviewStatisticsDue,
                    '${stats.dueNow}',
                    Icons.pending_actions_outlined,
                  ),
                  _MetricCard(
                    l10n.reviewStatisticsStreak,
                    '${stats.streak}',
                    Icons.local_fire_department_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ChartCard(
                title: l10n.reviewStatisticsTrend,
                child: SizedBox(
                  height: 190,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          isCurved: true,
                          color: Theme.of(context).colorScheme.primary,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          spots: [
                            for (var i = 0; i < stats.dailyTrend.length; i++)
                              FlSpot(
                                i.toDouble(),
                                stats.dailyTrend[i].reviewedCards.toDouble(),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ChartCard(
                title: l10n.reviewStatisticsUpcoming,
                child: SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        for (var i = 0; i < stats.upcomingDue.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: stats.upcomingDue[i].toDouble(),
                                color: Theme.of(context).colorScheme.secondary,
                                width: 18,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ChartCard(
                title:
                    '${l10n.reviewStatisticsRatings} · ${(stats.retentionRate * 100).round()}%',
                child: SizedBox(
                  height: 190,
                  child: stats.ratings.total == 0
                      ? Center(child: Text(l10n.reviewStatisticsEmptyRatings))
                      : PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 42,
                            sections: [
                              _pie('Again', stats.ratings.again, Colors.orange),
                              _pie('Hard', stats.ratings.hard, Colors.amber),
                              _pie('Good', stats.ratings.good, Colors.green),
                              _pie('Easy', stats.ratings.easy, Colors.blue),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _ChartCard(
                title: l10n.reviewStatisticsContent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _CountTile(
                      l10n.reviewStatisticsSentences,
                      stats.totalSentences,
                    ),
                    _CountTile(
                      l10n.reviewStatisticsVocabulary,
                      stats.totalVocabulary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static PieChartSectionData _pie(String title, int value, Color color) =>
      PieChartSectionData(
        value: value.toDouble(),
        color: color,
        title: value == 0 ? '' : '$value',
        radius: 58,
      );

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    return minutes == 0 ? '$seconds 秒' : '$minutes 分钟';
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _MetricCard(this.title, this.value, this.icon);

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _CountTile extends StatelessWidget {
  final String label;
  final int count;
  const _CountTile(this.label, this.count);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$count', style: Theme.of(context).textTheme.headlineMedium),
      Text(label),
    ],
  );
}
