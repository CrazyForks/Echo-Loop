import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../features/review_statistics/review_statistics_provider.dart';
import '../features/review_statistics/review_statistics_repository.dart';
import '../l10n/app_localizations.dart';

/// 收藏复习统计页，以学习数据日记的布局呈现既有统计结果。
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
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.list(
                  children: [
                    _ScopeSelector(
                      selected: notifier.scope,
                      onChanged: notifier.setScope,
                      l10n: l10n,
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(label: l10n.reviewStatisticsTodayReviewed),
                    const SizedBox(height: 10),
                    _MetricGrid(stats: stats, l10n: l10n),
                    const SizedBox(height: 24),
                    _JournalCard(
                      title: l10n.reviewStatisticsTrend,
                      child: _TrendChart(stats: stats),
                    ),
                    const SizedBox(height: 14),
                    _JournalCard(
                      title: l10n.reviewStatisticsUpcoming,
                      child: _UpcomingChart(stats: stats),
                    ),
                    const SizedBox(height: 14),
                    _JournalCard(
                      title: l10n.reviewStatisticsRatings,
                      subtitle: l10n.reviewStatisticsRetentionExplanation,
                      child: _RatingChart(stats: stats, l10n: l10n),
                    ),
                    const SizedBox(height: 14),
                    _JournalCard(
                      title: l10n.reviewStatisticsContent,
                      child: _ContentSummary(stats: stats, l10n: l10n),
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
}

class _ScopeSelector extends StatelessWidget {
  final ReviewStatisticsScope selected;
  final ValueChanged<ReviewStatisticsScope> onChanged;
  final AppLocalizations l10n;
  const _ScopeSelector({
    required this.selected,
    required this.onChanged,
    required this.l10n,
  });
  @override
  Widget build(BuildContext context) => SegmentedButton<ReviewStatisticsScope>(
    showSelectedIcon: false,
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
    selected: {selected},
    onSelectionChanged: (value) => onChanged(value.first),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.05,
    ),
  );
}

class _MetricGrid extends StatelessWidget {
  final ReviewStatistics stats;
  final AppLocalizations l10n;
  const _MetricGrid({required this.stats, required this.l10n});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 620;
      return GridView.count(
        crossAxisCount: wide ? 4 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: wide ? 1.35 : 1.5,
        children: [
          _MetricCard(
            l10n.reviewStatisticsTodayReviewed,
            '${stats.todayReviewedCards}',
            Icons.auto_graph_rounded,
            const Color(0xFF2B6C8F),
          ),
          _MetricCard(
            l10n.reviewStatisticsDuration,
            _formatDuration(stats.todaySeconds, l10n),
            Icons.timer_outlined,
            const Color(0xFF597C65),
          ),
          _MetricCard(
            l10n.reviewStatisticsDue,
            '${stats.dueNow}',
            Icons.hourglass_bottom_rounded,
            const Color(0xFFC56B45),
          ),
          _MetricCard(
            l10n.reviewStatisticsStreak,
            '${stats.streak}',
            Icons.local_fire_department_rounded,
            const Color(0xFFD88A36),
          ),
        ],
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color accent;
  const _MetricCard(this.label, this.value, this.icon, this.accent);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.38 : 0.18,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _JournalCard({required this.title, required this.child, this.subtitle});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.55 : 0.7,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final ReviewStatistics stats;
  const _TrendChart({required this.stats});
  @override
  Widget build(BuildContext context) {
    if (!stats.dailyTrend.any((day) => day.reviewedCards > 0)) {
      return const _ChartEmptyState(icon: Icons.show_chart_rounded);
    }
    final theme = Theme.of(context);
    const accent = Color(0xFF2B6C8F);
    final maxY = stats.dailyTrend
        .map((day) => day.reviewedCards)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.18,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 3).clamp(1, double.infinity),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 10,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 ||
                      index >= stats.dailyTrend.length ||
                      (index % 10 != 0 &&
                          index != stats.dailyTrend.length - 1)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      DateFormat('M/d').format(stats.dailyTrend[index].date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItems: (spots) => spots
                  .map(
                    (spot) => LineTooltipItem(
                      '${stats.dailyTrend[spot.x.toInt()].reviewedCards}',
                      TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              curveSmoothness: 0.28,
              color: accent,
              barWidth: 3.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.26),
                    accent.withValues(alpha: 0.01),
                  ],
                ),
              ),
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
    );
  }
}

class _UpcomingChart extends StatelessWidget {
  final ReviewStatistics stats;
  const _UpcomingChart({required this.stats});
  @override
  Widget build(BuildContext context) {
    if (!stats.upcomingDue.any((value) => value > 0)) {
      return const _ChartEmptyState(icon: Icons.event_available_outlined);
    }
    final theme = Theme.of(context);
    final now = DateTime.now();
    final maxY = stats.upcomingDue.reduce((a, b) => a > b ? a : b).toDouble();
    return SizedBox(
      height: 184,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 3).clamp(1, double.infinity),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= 7) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      DateFormat(
                        'E',
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(now.add(Duration(days: index))),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: index == 0
                            ? const Color(0xFFC56B45)
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: index == 0 ? FontWeight.w800 : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItem: (_, __, rod, ___) => BarTooltipItem(
                rod.toY.toInt().toString(),
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < stats.upcomingDue.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: stats.upcomingDue[i].toDouble(),
                    width: 18,
                    color: i == 0
                        ? const Color(0xFFC56B45)
                        : const Color(0xFF597C65),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                    label: BarChartRodLabel(
                      show: stats.upcomingDue[i] > 0,
                      text: '${stats.upcomingDue[i]}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: i == 0
                            ? const Color(0xFFC56B45)
                            : const Color(0xFF597C65),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingChart extends StatelessWidget {
  final ReviewStatistics stats;
  final AppLocalizations l10n;
  const _RatingChart({required this.stats, required this.l10n});
  @override
  Widget build(BuildContext context) {
    if (stats.ratings.total == 0) {
      return _ChartEmptyState(
        icon: Icons.donut_large_outlined,
        message: l10n.reviewStatisticsEmptyRatings,
      );
    }
    // 当前复习流程只提供三档评分；将历史“困难”记录归入“再来一遍”，
    // 让环图总量继续和保持率的分母一致，也不向用户暴露已下线的选项。
    final sections = [
      _RatingSlice(
        l10n.bookmarkReviewAgain,
        stats.ratings.again + stats.ratings.hard,
        const Color(0xFFC56B45),
      ),
      _RatingSlice(
        l10n.bookmarkReviewRatingGood,
        stats.ratings.good,
        const Color(0xFF4D9271),
      ),
      _RatingSlice(
        l10n.bookmarkReviewRatingEasy,
        stats.ratings.easy,
        const Color(0xFF2B6C8F),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final chart = SizedBox(
          width: 156,
          height: 156,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 49,
                  sections: [
                    for (final slice in sections)
                      PieChartSectionData(
                        value: slice.value.toDouble(),
                        color: slice.color,
                        radius: 30,
                        title: '',
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.reviewStatisticsRetentionRate,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${(stats.retentionRate * 100).round()}%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        final legend = Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final slice in sections) _LegendRow(slice: slice)],
        );
        return constraints.maxWidth < 380
            ? Column(children: [chart, const SizedBox(height: 12), legend])
            : Row(
                children: [
                  chart,
                  const SizedBox(width: 18),
                  Expanded(child: legend),
                ],
              );
      },
    );
  }
}

class _RatingSlice {
  final String label;
  final int value;
  final Color color;
  const _RatingSlice(this.label, this.value, this.color);
}

class _LegendRow extends StatelessWidget {
  final _RatingSlice slice;
  const _LegendRow({required this.slice});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: slice.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            slice.label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Text(
          '${slice.value}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _ContentSummary extends StatelessWidget {
  final ReviewStatistics stats;
  final AppLocalizations l10n;
  const _ContentSummary({required this.stats, required this.l10n});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ContentTile(
          label: l10n.reviewStatisticsSentences,
          count: stats.totalSentences,
          color: const Color(0xFF2B6C8F),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _ContentTile(
          label: l10n.reviewStatisticsVocabulary,
          count: stats.totalVocabulary,
          color: const Color(0xFF597C65),
        ),
      ),
    ],
  );
}

class _ContentTile extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _ContentTile({
    required this.label,
    required this.count,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _ChartEmptyState extends StatelessWidget {
  final IconData icon;
  final String? message;

  const _ChartEmptyState({required this.icon, this.message});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 30,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

String _formatDuration(int seconds, AppLocalizations l10n) {
  final minutes = seconds ~/ 60;
  if (l10n.localeName == 'zh') {
    return minutes == 0 ? '$seconds 秒' : '$minutes 分钟';
  }
  return minutes == 0 ? '${seconds}s' : '$minutes min';
}
