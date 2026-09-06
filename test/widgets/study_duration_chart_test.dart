import 'package:echo_loop/providers/study_duration_provider.dart';
import 'dart:async';
import 'package:echo_loop/widgets/common/app_segmented_button.dart';
import 'package:echo_loop/widgets/study/study_duration_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/models/study_stage.dart';
import 'package:echo_loop/services/study_time_service.dart';
import 'package:echo_loop/widgets/study/day_stage_breakdown_sheet.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });
  final currentWeek = StudyDurationBucket(
    periodStart: DateTime(2026, 8, 31),
    periodEnd: DateTime(2026, 9, 6),
    totalSeconds: 3900,
    inputSeconds: 1800,
    outputSeconds: 1200,
    otherSeconds: 900,
    isCurrentPeriod: true,
  );

  Widget buildChart({StudyTimeService? service}) {
    return ProviderScope(
      overrides: [
        studyTimeServiceProvider.overrideWithValue(
          service ??
              StudyTimeService(
                db.dailyStudyRecordDao,
                db.dailyStageStudyRecordDao,
              ),
        ),
        for (final granularity in StudyDurationGranularity.values)
          studyDurationBucketsProvider(granularity).overrideWith(
            (ref) async => [
              StudyDurationBucket(
                periodStart: switch (granularity) {
                  StudyDurationGranularity.day => DateTime(2026, 9, 1),
                  StudyDurationGranularity.week => currentWeek.periodStart,
                  StudyDurationGranularity.month => DateTime(2026, 9),
                  StudyDurationGranularity.year => DateTime(2026),
                },
                periodEnd: granularity == StudyDurationGranularity.day
                    ? DateTime(2026, 9, 1)
                    : currentWeek.periodEnd,
                totalSeconds: 3900,
                inputSeconds: 1800,
                outputSeconds: 1200,
                otherSeconds: 900,
                isCurrentPeriod: true,
              ),
            ],
          ),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: [Locale('zh')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: StudyDurationChart()),
      ),
    );
  }

  test('紧凑时长使用小时和分钟', () {
    expect(formatStudyDurationCompact(3900), '1h5m');
    expect(formatStudyDurationCompact(3600), '1h');
    expect(formatStudyDurationCompact(30), '<1m');
  });

  testWidgets('加载失败可重试，关闭后迟到结果不会重新打开弹窗', (tester) async {
    final service = _ControlledService(db);
    await tester.pumpWidget(buildChart(service: service));
    await tester.pumpAndSettle();
    final bar = find.text('1h5m');
    await tester.tap(bar);
    await tester.tap(bar, warnIfMissed: false);
    await tester.pump();
    expect(service.requests, hasLength(1));
    service.requests.first.completeError(StateError('query failed'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(service.requests, hasLength(2));
    Navigator.of(tester.element(find.byType(CircularProgressIndicator))).pop();
    service.requests.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(bar);
    await tester.pump();
    expect(service.requests, hasLength(3));
    service.requests.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(DayStageBreakdownSheet), findsOneWidget);
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

    expect(
      find.byType(AppSegmentedButton<StudyDurationGranularity>),
      findsOneWidget,
    );
    expect(
      find.byType(SegmentedButton<StudyDurationGranularity>),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byType(AppSegmentedButton<StudyDurationGranularity>))
          .height,
      30,
    );
    expect(
      tester
          .getSize(find.byType(AppSegmentedButton<StudyDurationGranularity>))
          .width,
      200,
    );
    expect(find.text('周'), findsOneWidget);
    expect(find.text('1h5m'), findsOneWidget);
    expect(find.text('听'), findsOneWidget);
    expect(find.text('说'), findsOneWidget);
    expect(find.text('其它 (思考、停顿等)'), findsOneWidget);

    await tester.tap(find.text('1h5m'));
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
    });
    await tester.pumpAndSettle();

    expect(find.byType(DayStageBreakdownSheet), findsOneWidget);
    expect(find.text('详细分布数据从此版本开始记录'), findsOneWidget);
  });

  for (final label in ['日', '周', '月', '年']) {
    testWidgets('$label柱体使用阶段明细并保留独立总量', (tester) async {
      await tester.runAsync(() async {
        for (final day in [1, 2]) {
          await db.dailyStageStudyRecordDao.upsertAdd(
            DateTime(2026, 9, day),
            StudyStage.intensiveListen,
            studyTime: 120,
            inputTime: 60,
            outputTime: 30,
          );
        }
        await db.dailyStageStudyRecordDao.upsertAdd(
          DateTime(2026, 9, 1),
          StudyStage.savedVocabularyReview,
          studyTime: 180,
        );
        await db.dailyStageStudyRecordDao.upsertAdd(
          DateTime(2026, 9, 1),
          StudyStage.savedSentencesReview,
          studyTime: 60,
        );
      });
      await tester.pumpWidget(buildChart());
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1h5m'));
      await tester.runAsync(() async {
        await tester.pumpAndSettle();
      });
      await tester.pumpAndSettle();
      expect(find.byType(DayStageBreakdownSheet), findsOneWidget);
      expect(find.text('精听'), findsOneWidget);
      expect(find.byIcon(Icons.subject), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      expect(find.text('词汇复习'), findsOneWidget);
      expect(find.text('单词复习'), findsNothing);
      expect(find.text(label == '日' ? '2分' : '4分'), findsOneWidget);
      expect(find.text('3分'), findsOneWidget);
      expect(
        find.text(label == '日' ? '听 1分 · 说 <1分' : '听 2分 · 说 1分'),
        findsOneWidget,
      );
      expect(find.text('合计'), findsOneWidget);
      expect(find.text('1h 5分'), findsOneWidget);
      expect(find.text('输入'), findsNothing);
      expect(find.text('输出'), findsNothing);
    });
  }

}

/// 用可控结果覆盖错误与迟到响应，无需任意延时。
class _ControlledService extends StudyTimeService {
  _ControlledService(AppDatabase db)
    : super(db.dailyStudyRecordDao, db.dailyStageStudyRecordDao);
  final requests = <Completer<List<DailyStageStudyRecordData>>>[];

  @override
  Future<List<DailyStageStudyRecordData>> getStageBreakdownInRange(
    DateTime start,
    DateTime end,
  ) {
    final request = Completer<List<DailyStageStudyRecordData>>();
    requests.add(request);
    return request.future;
  }
}
