import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/screens/review_statistics_screen.dart';
import 'package:echo_loop/l10n/app_localizations.dart';

void main() {
  testWidgets('统计页展示范围筛选和关键指标', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('zh')],
          home: ReviewStatisticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('收藏句子'), findsOneWidget);
    expect(find.text('收藏词汇'), findsOneWidget);
    expect(find.text('今日复习'), findsOneWidget);
  });
}
