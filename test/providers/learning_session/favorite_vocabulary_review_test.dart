import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:echo_loop/providers/learning_session/favorite_vocabulary_review_provider.dart';
import 'package:echo_loop/providers/pronunciation/pronunciation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePronunciationPlaybackController
    extends PronunciationPlaybackController {
  int stops = 0;
  final spoken = <String>[];

  @override
  PronunciationPlaybackState build() => const PronunciationPlaybackState();

  @override
  Future<void> speak(String text, {String? key}) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

db.SavedWord _word(String subjectId, String text) => db.SavedWord(
  id: subjectId.hashCode,
  word: text,
  memorySubjectId: subjectId,
  practiceCount: 0,
  totalStudyMs: 0,
  viewedBack: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  syncStatus: 0,
);

void main() {
  late db.AppDatabase database;
  late ProviderContainer container;
  late _FakePronunciationPlaybackController fakePlayback;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    fakePlayback = _FakePronunciationPlaybackController();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        pronunciationPlaybackProvider.overrideWith(() => fakePlayback),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('initialize builds the deck and starts on front', () async {
    await container.read(favoriteVocabularyReviewProvider.notifier).initialize([
      _word('w1', 'apple'),
      _word('w2', 'banana'),
    ], []);

    final state = container.read(favoriteVocabularyReviewProvider);
    expect(state.total, 2);
    expect(state.face, FavoriteVocabularyReviewFace.front);
    expect(state.currentCard?.displayText, isNotEmpty);
  });

  test(
    'replayCurrent speaks the current card via pronunciation provider',
    () async {
      final notifier = container.read(
        favoriteVocabularyReviewProvider.notifier,
      );
      await notifier.initialize([_word('w1', 'apple')], []);
      final card = container
          .read(favoriteVocabularyReviewProvider)
          .currentCard!;

      await notifier.replayCurrent();

      expect(fakePlayback.spoken, [card.displayText]);
      expect(
        container.read(favoriteVocabularyReviewProvider).playbackState,
        FavoriteVocabularyReviewPlaybackState.idle,
      );
    },
  );

  test('revealBack fetches ratings and submitting advances the deck', () async {
    final notifier = container.read(favoriteVocabularyReviewProvider.notifier);
    await notifier.initialize([
      _word('w1', 'apple'),
      _word('w2', 'banana'),
    ], []);

    await notifier.revealBack();

    final revealed = container.read(favoriteVocabularyReviewProvider);
    expect(revealed.face, FavoriteVocabularyReviewFace.back);
    expect(revealed.preview, isNotNull);
    expect(fakePlayback.stops, greaterThan(0));

    await notifier.selectRating(MemoryRating.good);

    final advanced = container.read(favoriteVocabularyReviewProvider);
    expect(advanced.face, FavoriteVocabularyReviewFace.front);
    expect(advanced.currentCard?.displayText, 'banana');
  });
}
