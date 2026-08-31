import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/providers/favorite_review_settings_provider.dart';
import 'package:echo_loop/theme/app_theme.dart';
import 'package:echo_loop/widgets/bookmark_review/bookmark_review_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget buildSheet(
    ProviderContainer container,
    FavoriteReviewSettingsTask task,
  ) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: Scaffold(body: BookmarkReviewSettingsSheet(task: task)),
    ),
  );

  testWidgets('从收藏句入口打开时，句子专属设置默认展开', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      buildSheet(container, FavoriteReviewSettingsTask.sentence),
    );
    await tester.pumpAndSettle();

    expect(find.text('自动显示 AI 讲解', skipOffstage: false), findsOneWidget);
    expect(find.text('正面显示词汇'), findsNothing);

    final vocabularySection = find.byKey(
      const Key('favorite-review-settings-vocabulary-section'),
    );
    await tester.ensureVisible(vocabularySection);
    await tester.tap(vocabularySection);
    await tester.pumpAndSettle();

    expect(find.text('正面显示词汇', skipOffstage: false), findsOneWidget);
  });

  testWidgets('词汇专属开关写入共用复习设置', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      buildSheet(container, FavoriteReviewSettingsTask.vocabulary),
    );
    await tester.pumpAndSettle();

    final showVocabularySwitch = find.descendant(
      of: find.byKey(const Key('favorite-review-show-vocabulary-on-front')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(showVocabularySwitch);
    await tester.tap(showVocabularySwitch);
    await tester.pump();

    expect(
      container.read(favoriteReviewSettingsProvider).showVocabularyOnFront,
      isTrue,
    );
  });
}
