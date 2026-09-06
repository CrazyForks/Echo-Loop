import 'package:echo_loop/providers/study_duration_provider.dart';
import 'package:echo_loop/widgets/study/study_duration_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final currentWeek = StudyDurationBucket(
    periodStart: DateTime(2026, 8, 31),
    periodEnd: DateTime(2026, 9, 6),
    totalSeconds: 3900,
    inputSeconds: 1800,
    outputSeconds: 1200,
    otherSeconds: 900,
    isCurrentPeriod: true,
  );

  Widget buildChart() {
    return ProviderScope(
      overrides: [
        studyDurationBucketsProvider(
          StudyDurationGranularity.week,
        ).overrideWith((ref) async => [currentWeek]),
      ],
      child: const MaterialApp(home: Scaffold(body: StudyDurationChart())),
    );
  }

  test('紧凑时长使用小时和分钟', () {
    expect(formatStudyDurationCompact(3900), '1h5m');
    expect(formatStudyDurationCompact(3600), '1h');
    expect(formatStudyDurationCompact(30), '<1m');
  });

  test('周期标签优先显示本期和上期', () {
    final now = DateTime(2026, 9, 6);
    expect(
      formatStudyDurationBucketLabel(
        bucket: currentWeek,
        granularity: StudyDurationGranularity.week,
        now: now,
        isZh: true,
      ),
      '本周',
    );
    expect(
      formatStudyDurationBucketLabel(
        bucket: StudyDurationBucket(
          periodStart: DateTime(2026, 7, 6),
          periodEnd: DateTime(2026, 7, 12),
          totalSeconds: 0,
          inputSeconds: 0,
          outputSeconds: 0,
          otherSeconds: 0,
          isCurrentPeriod: false,
        ),
        granularity: StudyDurationGranularity.week,
        now: now,
        isZh: true,
      ),
      '7/6-12',
    );
  });

  testWidgets('周视图默认选中且柱体点击显示底部明细', (tester) async {
    await tester.pumpWidget(buildChart());
    await tester.pumpAndSettle();

    final selector = tester.widget<SegmentedButton<StudyDurationGranularity>>(
      find.byType(SegmentedButton<StudyDurationGranularity>),
    );
    expect(selector.selected, {StudyDurationGranularity.week});
    expect(selector.showSelectedIcon, isFalse);
    expect(find.text('1h5m'), findsOneWidget);

    await tester.tap(find.text('1h5m'));
    await tester.pumpAndSettle();

    expect(find.text('总时长'), findsOneWidget);
    expect(find.text('1h5m'), findsNWidgets(2));
  });
}
