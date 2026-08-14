import 'dart:async';

import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/database/daos/bookmark_dao.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/models/audio_engine_state.dart';
import 'package:echo_loop/models/sentence.dart';
import 'package:echo_loop/providers/audio_engine/audio_engine_provider.dart';
import 'package:echo_loop/providers/audio_engine/foreground_audio_engine_provider.dart';
import 'package:echo_loop/providers/learning_session/bookmark_review_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import '../../helpers/mock_providers.dart';

class _TestBookmarkDao implements BookmarkDao {
  _TestBookmarkDao({this.fail = false});
  final bool fail;
  final removed = <(String, int)>[];

  @override
  Future<void> removeBookmark(String audioItemId, int sentenceIndex) async {
    if (fail) throw StateError('failed');
    removed.add((audioItemId, sentenceIndex));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeForegroundEngine extends ForegroundAudioEngine {
  int stops = 0;
  int sessions = 0;
  int rangePlays = 0;
  Completer<void>? pendingRangePlay;
  @override
  AudioEngineState build() => const AudioEngineState(currentAudioId: 'audio-1');
  @override
  Future<void> stop() async => stops++;
  @override
  int newSession() => ++sessions;
  @override
  Future<void> playClipOnce(Sentence sentence, int sessionId) async {}
  @override
  Future<void> playRangeForAudio(
    String audioItemId,
    Duration start,
    Duration end, {
    required double speed,
  }) {
    rangePlays++;
    return (pendingRangePlay ??= Completer<void>()).future;
  }
}

BookmarkWithAudio _bookmark(int id) => BookmarkWithAudio(
  bookmark: db.Bookmark(
    id: id,
    audioItemId: 'audio-1',
    memorySubjectId: 'test-subject-$id',
    sentenceIndex: id,
    sentenceText: 'Sentence $id',
    startTime: id.toDouble(),
    endTime: id + 1.0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    syncStatus: 0,
  ),
  audioName: 'Material',
);

ProviderContainer _container(_TestBookmarkDao dao, db.AppDatabase database) =>
    ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        bookmarkDaoProvider.overrideWithValue(dao),
        foregroundAudioEngineProvider.overrideWith(_FakeForegroundEngine.new),
        audioEngineProvider.overrideWith(TestAudioEngine.new),
        analyticsOverride(),
      ],
    );

({ProviderContainer container, db.AppDatabase database}) _testScope(
  _TestBookmarkDao dao,
) {
  final database = db.AppDatabase(NativeDatabase.memory());
  return (container: _container(dao, database), database: database);
}

void main() {
  test('initialize filters invalid bookmarks and starts on front', () async {
    final scope = _testScope(_TestBookmarkDao());
    final database = scope.database;
    final container = scope.container;
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    final invalid = BookmarkWithAudio(
      bookmark: _bookmark(9).bookmark.copyWith(endTime: 9),
      audioName: 'Material',
    );
    await container.read(bookmarkReviewProvider.notifier).initialize([
      _bookmark(1),
      invalid,
    ]);
    final state = container.read(bookmarkReviewProvider);
    expect(state.total, 1);
    expect(state.face, BookmarkReviewFace.front);
    expect(state.currentCard?.sentence.text, 'Sentence 1');
  });

  test('reveal stops playback and exposes placeholder back', () async {
    final scope = _testScope(_TestBookmarkDao());
    final container = scope.container;
    addTearDown(() async {
      container.dispose();
      await scope.database.close();
    });
    final notifier = container.read(bookmarkReviewProvider.notifier);
    await notifier.initialize([_bookmark(1)]);
    await notifier.revealBack();
    expect(
      container.read(bookmarkReviewProvider).face,
      BookmarkReviewFace.back,
    );
    expect(
      (container.read(foregroundAudioEngineProvider.notifier)
              as _FakeForegroundEngine)
          .stops,
      greaterThan(0),
    );
  });

  test('back can play and stop the current sentence', () async {
    final scope = _testScope(_TestBookmarkDao());
    final container = scope.container;
    addTearDown(() async {
      container.dispose();
      await scope.database.close();
    });
    final notifier = container.read(bookmarkReviewProvider.notifier);
    await notifier.initialize([_bookmark(1)]);
    await notifier.revealBack();

    final playback = notifier.toggleCurrentPlayback();
    await Future<void>.delayed(Duration.zero);
    final engine =
        container.read(foregroundAudioEngineProvider.notifier)
            as _FakeForegroundEngine;
    expect(engine.rangePlays, 1);
    expect(
      container.read(bookmarkReviewProvider).playbackState,
      BookmarkReviewPlaybackState.playing,
    );

    await notifier.toggleCurrentPlayback();
    expect(engine.stops, greaterThan(0));
    expect(
      container.read(bookmarkReviewProvider).playbackState,
      BookmarkReviewPlaybackState.idle,
    );
    final pendingRangePlay = engine.pendingRangePlay;
    expect(pendingRangePlay, isNotNull);
    pendingRangePlay?.complete();
    await playback;
  });

  test('successful unsave removes current card and advances', () async {
    final dao = _TestBookmarkDao();
    final scope = _testScope(dao);
    final container = scope.container;
    addTearDown(() async {
      container.dispose();
      await scope.database.close();
    });
    final notifier = container.read(bookmarkReviewProvider.notifier);
    await notifier.initialize([_bookmark(1), _bookmark(2)]);
    final removed = container.read(bookmarkReviewProvider).currentCard!;
    await notifier.removeCurrentBookmark();
    expect(dao.removed, [(removed.audioItemId, removed.originalSentenceIndex)]);
    expect(container.read(bookmarkReviewProvider).total, 1);
    expect(
      container.read(bookmarkReviewProvider).face,
      BookmarkReviewFace.front,
    );
  });

  test('failed unsave keeps current card', () async {
    final scope = _testScope(_TestBookmarkDao(fail: true));
    final container = scope.container;
    addTearDown(() async {
      container.dispose();
      await scope.database.close();
    });
    final notifier = container.read(bookmarkReviewProvider.notifier);
    await notifier.initialize([_bookmark(1)]);
    await notifier.removeCurrentBookmark();
    final state = container.read(bookmarkReviewProvider);
    expect(state.total, 1);
    expect(state.removeError, isNotNull);
    expect(state.isRemoving, isFalse);
  });
}
