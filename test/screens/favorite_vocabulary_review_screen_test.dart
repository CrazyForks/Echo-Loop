import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/models/flashcard_item.dart';
import 'package:echo_loop/providers/learning_session/favorite_vocabulary_review_provider.dart';
import 'package:echo_loop/screens/favorite_vocabulary_review_screen.dart';
import 'package:echo_loop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SavedWord _word(String text, {required String memorySubjectId}) => SavedWord(
  id: memorySubjectId.hashCode,
  word: text,
  memorySubjectId: memorySubjectId,
  practiceCount: 0,
  totalStudyMs: 0,
  viewedBack: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  syncStatus: 0,
);

class _TestFavoriteVocabularyReview extends FavoriteVocabularyReview {
  @override
  FavoriteVocabularyReviewState build() {
    return FavoriteVocabularyReviewState(
      cards: [
        FlashcardWordItem(savedWord: _word('apple', memorySubjectId: 'w-1')),
      ],
    );
  }

  @override
  Future<void> startCurrentCard() async {}

  @override
  Future<void> replayCurrent() async {
    state = state.copyWith(
      playbackState: FavoriteVocabularyReviewPlaybackState.playing,
    );
  }

  @override
  Future<void> interruptPlayback() async {
    state = state.copyWith(
      playbackState: FavoriteVocabularyReviewPlaybackState.idle,
    );
  }

  @override
  Future<void> revealBack() async {
    state = state.copyWith(face: FavoriteVocabularyReviewFace.back);
  }

  @override
  Future<void> disposeSession() async {}
}

Widget _app() => ProviderScope(
  overrides: [
    favoriteVocabularyReviewProvider.overrideWith(
      _TestFavoriteVocabularyReview.new,
    ),
  ],
  child: MaterialApp(
    locale: const Locale('zh'),
    theme: AppTheme.light(),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const FavoriteVocabularyReviewScreen(),
  ),
);

void main() {
  testWidgets('front shows title, progress bar and equal listen/reveal split', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.text('收藏词汇复习'), findsOneWidget);
    expect(
      find.byKey(const Key('favorite-vocabulary-review-progress')),
      findsOneWidget,
    );
    final listen = tester.getSize(
      find.byKey(const Key('favorite-vocabulary-review-listen-zone')),
    );
    final reveal = tester.getSize(
      find.byKey(const Key('favorite-vocabulary-review-reveal-zone')),
    );
    expect(reveal.height / listen.height, closeTo(1, 0.02));
  });

  testWidgets('upper zone replays and lower zone reveals the back placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('favorite-vocabulary-review-listen-zone')),
    );
    await tester.pump();
    expect(find.text('正在播放'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('favorite-vocabulary-review-reveal-zone')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('favorite-vocabulary-review-back-placeholder')),
      findsOneWidget,
    );
    expect(find.text('反面正在开发中'), findsOneWidget);
  });
}
