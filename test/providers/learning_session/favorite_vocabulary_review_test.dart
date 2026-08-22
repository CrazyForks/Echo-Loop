import 'dart:async';

import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/database/daos/saved_word_dao.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:echo_loop/providers/learning_session/favorite_vocabulary_review_provider.dart';
import 'package:echo_loop/providers/favorite_review_settings_provider.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_schedule.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_subject_ref.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_namespaces.dart';
import 'package:echo_loop/features/memory_scheduler/providers/memory_scheduler_providers.dart';
import 'package:echo_loop/models/favorite_review_settings.dart';
import 'package:echo_loop/models/flashcard_item.dart';
import 'package:echo_loop/providers/pronunciation/pronunciation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTextPlaybackController extends TextPlaybackController {
  int stops = 0;
  final spoken = <String>[];
  bool holdSpeak = false;
  Completer<void>? pendingSpeak;

  @override
  TextPlaybackState build() => const TextPlaybackState();

  @override
  Future<void> speak(String text, {String? key}) async {
    spoken.add(text);
    if (holdSpeak) {
      final pending = pendingSpeak ??= Completer<void>();
      await pending.future;
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    pendingSpeak?.complete();
    pendingSpeak = null;
  }
}

class _TestFavoriteReviewSettings extends FavoriteReviewSettingsNotifier {
  _TestFavoriteReviewSettings(this.autoPlayFront);

  final bool autoPlayFront;

  @override
  FavoriteReviewSettings build() =>
      FavoriteReviewSettings(autoPlayFront: autoPlayFront);
}

class _FailingSavedWordDao extends SavedWordDao {
  _FailingSavedWordDao(super.database);

  @override
  Future<void> removeWord(String word) => throw StateError('remove failed');
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
  late _FakeTextPlaybackController fakePlayback;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    fakePlayback = _FakeTextPlaybackController();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        textPlaybackProvider.overrideWith(() => fakePlayback),
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
    expect(state.initialTotal, 2);
    expect(state.face, FavoriteVocabularyReviewFace.front);
    expect(state.currentCard?.displayText, isNotEmpty);
  });

  test(
    'replayCurrent uses the shared speech path for a single-word card',
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
        container.read(favoriteVocabularyReviewProvider).wordPlaybackState,
        FavoriteVocabularyReviewPlaybackState.idle,
      );
    },
  );

  test(
    'replayCurrent keeps multi-word cards on the existing speech path',
    () async {
      final notifier = container.read(
        favoriteVocabularyReviewProvider.notifier,
      );
      await notifier.initialize([_word('w1', 'hello world')], []);

      await notifier.replayCurrent();

      expect(fakePlayback.spoken, ['hello world']);
    },
  );

  test('shared front auto-play setting controls vocabulary playback', () async {
    final disabledContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        textPlaybackProvider.overrideWith(() => fakePlayback),
        favoriteReviewSettingsProvider.overrideWith(
          () => _TestFavoriteReviewSettings(false),
        ),
      ],
    );
    addTearDown(disabledContainer.dispose);
    final notifier = disabledContainer.read(
      favoriteVocabularyReviewProvider.notifier,
    );
    await notifier.initialize([_word('w1', 'apple')], []);
    await notifier.startCurrentCard();
    expect(fakePlayback.spoken, isEmpty);
  });

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

  test(
    'rating the last card stops word playback before showing completion',
    () async {
      final notifier = container.read(
        favoriteVocabularyReviewProvider.notifier,
      );
      await notifier.initialize([_word('w1', 'apple')], []);
      await notifier.revealBack();

      fakePlayback.holdSpeak = true;
      final playback = notifier.replayCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(favoriteVocabularyReviewProvider).wordPlaybackState,
        FavoriteVocabularyReviewPlaybackState.playing,
      );

      await notifier.selectRating(MemoryRating.good);
      await playback;

      expect(fakePlayback.stops, greaterThan(0));
      expect(
        container.read(favoriteVocabularyReviewProvider).currentCard,
        isNull,
      );
      expect(
        container.read(favoriteVocabularyReviewProvider).completionSummary,
        isNotNull,
      );
    },
  );

  test('unsaving a word archives its schedule and advances the deck', () async {
    final notifier = container.read(favoriteVocabularyReviewProvider.notifier);
    await database.savedWordDao.saveWord(word: 'apple');
    final first = (await database.savedWordDao.getAll()).single;
    await notifier.initialize([first, _word('w2', 'banana')], []);
    final removed = switch (container
        .read(favoriteVocabularyReviewProvider)
        .currentCard) {
      FlashcardWordItem item => item,
      _ => throw StateError('current card must be a word'),
    };

    await notifier.removeCurrentVocabulary();

    final state = container.read(favoriteVocabularyReviewProvider);
    expect(state.currentCard?.dbKey, isNot(removed.dbKey));
    expect(
      await database.savedWordDao.isWordSaved(removed.savedWord.word),
      isFalse,
    );
    final subjectId = removed.memorySubjectId;
    if (subjectId == null) fail('saved word must have a memory subject ID');
    final schedule = await container
        .read(memorySchedulerProvider)
        .getSchedule(
          MemorySubjectRef(
            namespace: kSavedWordOrPhraseNamespace,
            subjectId: subjectId,
          ),
        );
    expect(schedule?.status, MemoryScheduleStatus.archived);
  });

  test(
    'unsaving a sense group archives its schedule and completes the deck',
    () async {
      final notifier = container.read(
        favoriteVocabularyReviewProvider.notifier,
      );
      await database.savedSenseGroupDao.saveSenseGroup(
        phraseText: 'on the table',
        displayText: 'on the table',
      );
      final first = (await database.savedSenseGroupDao.watchAll().first).single;
      await notifier.initialize([], [first]);

      await notifier.removeCurrentVocabulary();

      final state = container.read(favoriteVocabularyReviewProvider);
      expect(state.currentCard, isNull);
      expect(
        await database.savedSenseGroupDao.isSenseGroupSaved(first.phraseText),
        isFalse,
      );
      final subjectId = first.memorySubjectId;
      if (subjectId == null) {
        fail('saved sense group must have a memory subject ID');
      }
      final schedule = await container
          .read(memorySchedulerProvider)
          .getSchedule(
            MemorySubjectRef(
              namespace: kSavedSenseGroupNamespace,
              subjectId: subjectId,
            ),
          );
      expect(schedule?.status, MemoryScheduleStatus.archived);
    },
  );

  test('failed unsave keeps the current card and exposes an error', () async {
    final failingContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        textPlaybackProvider.overrideWith(() => fakePlayback),
        savedWordDaoProvider.overrideWithValue(_FailingSavedWordDao(database)),
      ],
    );
    addTearDown(failingContainer.dispose);
    final notifier = failingContainer.read(
      favoriteVocabularyReviewProvider.notifier,
    );
    await notifier.initialize([_word('w1', 'apple')], []);

    await notifier.removeCurrentVocabulary();

    final state = failingContainer.read(favoriteVocabularyReviewProvider);
    expect(state.currentCard?.displayText, 'apple');
    expect(state.isRemoving, isFalse);
    expect(state.removeError, 'unsave_failed');
  });
}
