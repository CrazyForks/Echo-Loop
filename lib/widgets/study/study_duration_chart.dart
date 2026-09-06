import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/study_duration_provider.dart';
import '../../theme/app_theme.dart';
import '../common/app_segmented_button.dart';
import 'day_stage_breakdown_sheet.dart';
import 'study_stats_header.dart';

/// 学习日历下方的历史学习时长统计。
class StudyDurationChart extends ConsumerStatefulWidget {
  const StudyDurationChart({super.key});

  @override
  ConsumerState<StudyDurationChart> createState() => _StudyDurationChartState();
}

class _StudyDurationChartState extends ConsumerState<StudyDurationChart> {
  StudyDurationGranularity _granularity = StudyDurationGranularity.week;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studyDurationBucketsProvider(_granularity));
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isZh ? '学习时长' : 'Study duration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Center(
              child: AppSegmentedButton<StudyDurationGranularity>(
                minimumHeight: 30,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                segments: [
                  ButtonSegment(
                    value: StudyDurationGranularity.day,
                    label: Text(isZh ? '日' : 'Day'),
                  ),
                  ButtonSegment(
                    value: StudyDurationGranularity.week,
                    label: Text(isZh ? '周' : 'Week'),
                  ),
                  ButtonSegment(
                    value: StudyDurationGranularity.month,
                    label: Text(isZh ? '月' : 'Month'),
                  ),
                  ButtonSegment(
                    value: StudyDurationGranularity.year,
                    label: Text(isZh ? '年' : 'Year'),
                  ),
                ],
                selected: {_granularity},
                onSelectionChanged: (value) {
                  if (value.isEmpty) return;
                  setState(() => _granularity = value.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            async.when(
              loading: () => const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _ErrorState(
                onRetry: () => ref.invalidate(studyDurationRecordsProvider),
              ),
              data: (buckets) =>
                  buckets.every((bucket) => bucket.totalSeconds == 0)
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: Text('No study records')),
                    )
                  : _BucketList(
                      key: ValueKey(_granularity),
                      buckets: buckets,
                      controller: _scrollController,
                      granularity: _granularity,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 100,
    child: Center(
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    ),
  );
}

class _BucketList extends StatefulWidget {
  final List<StudyDurationBucket> buckets;
  final ScrollController controller;
  final StudyDurationGranularity granularity;
  const _BucketList({
    super.key,
    required this.buckets,
    required this.controller,
    required this.granularity,
  });

  @override
  State<_BucketList> createState() => _BucketListState();
}

class _BucketListState extends State<_BucketList> {
  @override
  void initState() {
    super.initState();
    // 每个粒度创建一次列表，在首帧布局完成后定位到当前周期。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      widget.controller.jumpTo(widget.controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    var maxValue = 1;
    for (final bucket in widget.buckets) {
      if (bucket.totalSeconds > maxValue) maxValue = bucket.totalSeconds;
    }
    return SizedBox(
      height: 150,
      child: ListView.builder(
        controller: widget.controller,
        scrollDirection: Axis.horizontal,
        itemExtent: 58,
        cacheExtent: 58 * 8,
        itemCount: widget.buckets.length,
        itemBuilder: (context, index) {
          final bucket = widget.buckets[index];
          final height = bucket.totalSeconds == 0
              ? 3.0
              : 90 * bucket.totalSeconds / maxValue;
          final label = formatStudyDurationBucketLabel(
            bucket: bucket,
            granularity: widget.granularity,
            now: DateTime.now(),
            isZh: Localizations.localeOf(context).languageCode == 'zh',
          );
          return Semantics(
            label:
                '${bucket.periodStart} - ${bucket.periodEnd}, ${bucket.totalSeconds} seconds${bucket.isCurrentPeriod ? ', current period' : ''}',
            button: true,
            child: GestureDetector(
              onLongPress: () => _showTooltip(context, bucket),
              onTap: () => _showTooltip(context, bucket),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    bucket.totalSeconds == 0
                        ? ''
                        : formatStudyDurationCompact(bucket.totalSeconds),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 30,
                    height: height,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _StackedBar(bucket: bucket),
                  ),
                  const SizedBox(height: 5),
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showTooltip(BuildContext context, StudyDurationBucket bucket) {
    showStudyDurationBreakdownSheet(
      context: context,
      periodLabel: formatStudyDurationBucketLabel(
        bucket: bucket,
        granularity: widget.granularity,
        now: DateTime.now(),
        isZh: Localizations.localeOf(context).languageCode == 'zh',
      ),
      totalSeconds: bucket.totalSeconds,
      inputSeconds: bucket.inputSeconds,
      outputSeconds: bucket.outputSeconds,
      otherSeconds: bucket.otherSeconds,
    );
  }
}

/// 使用紧凑的小时和分钟格式展示学习时长。
String formatStudyDurationCompact(int seconds) {
  if (seconds > 0 && seconds < 60) return '<1m';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return minutes > 0 ? '${hours}h${minutes}m' : '${hours}h';
  return '${minutes}m';
}

/// 按粒度生成易读的时间轴标签，并优先标识当前和上一周期。
String formatStudyDurationBucketLabel({
  required StudyDurationBucket bucket,
  required StudyDurationGranularity granularity,
  required DateTime now,
  required bool isZh,
}) {
  final currentStart = _periodStart(now, granularity);
  final previousStart = _previousPeriodStart(currentStart, granularity);
  if (_sameDate(bucket.periodStart, currentStart)) {
    return isZh ? _currentLabel(granularity) : _currentLabelEn(granularity);
  }
  if (_sameDate(bucket.periodStart, previousStart)) {
    return isZh ? _previousLabel(granularity) : _previousLabelEn(granularity);
  }
  if (granularity == StudyDurationGranularity.year) {
    return '${bucket.periodStart.year}';
  }
  if (granularity == StudyDurationGranularity.month) {
    return '${bucket.periodStart.month}/1-${bucket.periodEnd.day}';
  }
  if (granularity == StudyDurationGranularity.week) {
    final start = bucket.periodStart;
    final end = bucket.periodEnd;
    return start.month == end.month
        ? '${start.month}/${start.day}-${end.day}'
        : '${start.month}/${start.day}-${end.month}/${end.day}';
  }
  return '${bucket.periodStart.month}/${bucket.periodStart.day}';
}

DateTime _periodStart(DateTime date, StudyDurationGranularity granularity) {
  final normalized = DateTime(date.year, date.month, date.day);
  return switch (granularity) {
    StudyDurationGranularity.day => normalized,
    StudyDurationGranularity.week => normalized.subtract(
      Duration(days: normalized.weekday - DateTime.monday),
    ),
    StudyDurationGranularity.month => DateTime(date.year, date.month),
    StudyDurationGranularity.year => DateTime(date.year),
  };
}

DateTime _previousPeriodStart(
  DateTime currentStart,
  StudyDurationGranularity granularity,
) => switch (granularity) {
  StudyDurationGranularity.day => currentStart.subtract(
    const Duration(days: 1),
  ),
  StudyDurationGranularity.week => currentStart.subtract(
    const Duration(days: 7),
  ),
  StudyDurationGranularity.month => DateTime(
    currentStart.year,
    currentStart.month - 1,
  ),
  StudyDurationGranularity.year => DateTime(currentStart.year - 1),
};

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _currentLabel(StudyDurationGranularity granularity) =>
    switch (granularity) {
      StudyDurationGranularity.day => '今天',
      StudyDurationGranularity.week => '本周',
      StudyDurationGranularity.month => '本月',
      StudyDurationGranularity.year => '今年',
    };

String _previousLabel(StudyDurationGranularity granularity) =>
    switch (granularity) {
      StudyDurationGranularity.day => '昨天',
      StudyDurationGranularity.week => '上周',
      StudyDurationGranularity.month => '上月',
      StudyDurationGranularity.year => '去年',
    };

String _currentLabelEn(StudyDurationGranularity granularity) =>
    switch (granularity) {
      StudyDurationGranularity.day => 'Today',
      StudyDurationGranularity.week => 'This week',
      StudyDurationGranularity.month => 'This month',
      StudyDurationGranularity.year => 'This year',
    };

String _previousLabelEn(StudyDurationGranularity granularity) =>
    switch (granularity) {
      StudyDurationGranularity.day => 'Yesterday',
      StudyDurationGranularity.week => 'Last week',
      StudyDurationGranularity.month => 'Last month',
      StudyDurationGranularity.year => 'Last year',
    };

class _StackedBar extends StatelessWidget {
  final StudyDurationBucket bucket;
  const _StackedBar({required this.bucket});
  @override
  Widget build(BuildContext context) {
    final total = bucket.totalSeconds;
    if (total <= 0) {
      return Container(color: Theme.of(context).colorScheme.outlineVariant);
    }
    return Column(
      children: [
        if (bucket.otherSeconds > 0)
          Expanded(
            flex: bucket.otherSeconds,
            child: Container(color: kOtherColor),
          ),
        if (bucket.outputSeconds > 0)
          Expanded(
            flex: bucket.outputSeconds,
            child: Container(color: kOutputColor),
          ),
        if (bucket.inputSeconds > 0)
          Expanded(
            flex: bucket.inputSeconds,
            child: Container(color: kInputColor),
          ),
      ],
    );
  }
}
