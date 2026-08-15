import 'package:echo_loop/utils/time_format.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(initTimeago);

  testWidgets('formats Chinese past and future relative times', (tester) async {
    late BuildContext context;
    final now = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [const Locale('zh'), const Locale('en')],
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      formatTimeAgo(context, now.subtract(const Duration(minutes: 5))),
      '5分钟前',
    );
    expect(
      formatTimeFromNow(context, now.add(const Duration(hours: 3))),
      '3小时后',
    );
    expect(
      formatTimeFromNow(context, now.add(const Duration(days: 16))),
      '16天后',
    );
    final nextReviewAt = now.add(const Duration(hours: 3));
    expect(
      formatNextReviewTimeDetail(
        context,
        showNextReviewTime: false,
        dueAt: nextReviewAt,
      ),
      isNull,
    );
    expect(
      formatNextReviewTimeDetail(
        context,
        showNextReviewTime: true,
        dueAt: null,
      ),
      isNull,
    );
    expect(
      formatNextReviewTimeDetail(
        context,
        showNextReviewTime: true,
        dueAt: nextReviewAt,
      ),
      '3小时后',
    );
    expect(
      formatTimeFromNow(
        context,
        DateTime.now().add(const Duration(seconds: 10)),
      ),
      matches(RegExp(r'^\d+秒后$')),
    );
    expect(
      formatTimeFromNow(
        context,
        DateTime.now().add(const Duration(seconds: 45)),
      ),
      matches(RegExp(r'^\d+秒后$')),
    );
    expect(
      formatTimeFromNow(
        context,
        DateTime.now().add(const Duration(seconds: 59)),
      ),
      matches(RegExp(r'^\d+秒后$')),
    );
  });

  testWidgets('formats English future relative times', (tester) async {
    late BuildContext context;
    final now = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [const Locale('zh'), const Locale('en')],
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      formatTimeFromNow(context, now.add(const Duration(minutes: 9))),
      'in 9 minutes',
    );
    expect(
      formatTimeFromNow(
        context,
        DateTime.now().add(const Duration(seconds: 10)),
      ),
      matches(RegExp(r'^in \d+ seconds$')),
    );
  });
}
