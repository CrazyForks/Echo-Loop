import 'dart:async';
import 'dart:io';

import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/database/daos/bookmark_dao.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:echo_loop/models/favorite_review_settings.dart';
import 'package:echo_loop/providers/audio_engine/audio_engine_provider.dart';
import 'package:echo_loop/providers/audio_engine/foreground_audio_engine_provider.dart';
import 'package:echo_loop/providers/favorite_review_settings_provider.dart';
import 'package:echo_loop/providers/learning_session/bookmark_review_provider.dart';
import 'package:echo_loop/providers/short_audio_player_provider.dart';
import 'package:echo_loop/services/pronunciation/local_audio_clip_player.dart';
import 'package:echo_loop/utils/app_data_dir.dart' as app_data_dir;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

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

class _FakeShortAudioPlayer extends LocalAudioClipPlayer {
  _FakeShortAudioPlayer() : super(backend: UnavailableAudioClipPlayerBackend());

  int stops = 0;
  int rangePlays = 0;
  final paths = <String>[];
  final ranges = <(Duration, Duration)>[];
  Completer<AudioPlaybackResult>? pendingRangePlay;
  String? _playingKey;

  @override
  LocalAudioClipPlaybackState get state =>
      LocalAudioClipPlaybackState(playingKey: _playingKey);

  @override
  Future<AudioPlaybackResult> playRangeFile(
    String filePath, {
    required Duration start,
    required Duration end,
    String? playbackKey,
  }) {
    rangePlays++;
    paths.add(filePath);
    ranges.add((start, end));
    _playingKey = playbackKey;
    return (pendingRangePlay ??= Completer<AudioPlaybackResult>()).future;
  }

  @override
  Future<void> stop() async {
    stops++;
    _playingKey = null;
    pendingRangePlay?.complete(AudioPlaybackResult.cancelled);
    pendingRangePlay = null;
  }

  void completeRange(AudioPlaybackResult result) {
    _playingKey = null;
    pendingRangePlay?.complete(result);
    pendingRangePlay = null;
  }
}

class _RecordingForegroundAudioEngine extends TestForegroundAudioEngine {
  int stopCalls = 0;

  @override
  Future<void> stop() async {
    stopCalls++;
    await super.stop();
  }
}

class _TestFavoriteReviewSettings extends FavoriteReviewSettingsNotifier {
  _TestFavoriteReviewSettings({
    required this.autoPlayFront,
    required this.autoPlayBack,
  });

  final bool autoPlayFront;
  final bool autoPlayBack;

  @override
  FavoriteReviewSettings build() => FavoriteReviewSettings(
    autoPlayFront: autoPlayFront,
    autoPlayBack: autoPlayBack,
  );
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

ProviderContainer _container(
  _TestBookmarkDao dao,
  db.AppDatabase database, {
  required _FakeShortAudioPlayer shortAudioPlayer,
  bool autoPlayFront = false,
  bool autoPlayBack = false,
}) => ProviderContainer(
  overrides: [
    appDatabaseProvider.overrideWithValue(database),
    bookmarkDaoProvider.overrideWithValue(dao),
    audioEngineProvider.overrideWith(TestAudioEngine.new),
    foregroundAudioEngineProvider.overrideWith(
      _RecordingForegroundAudioEngine.new,
    ),
    shortAudioPlayerProvider.overrideWithValue(shortAudioPlayer),
    favoriteReviewSettingsProvider.overrideWith(
      () => _TestFavoriteReviewSettings(
        autoPlayFront: autoPlayFront,
        autoPlayBack: autoPlayBack,
      ),
    ),
    analyticsOverride(),
  ],
);

({
  ProviderContainer container,
  db.AppDatabase database,
  _FakeShortAudioPlayer player,
})
_testScope(
  _TestBookmarkDao dao, {
  bool autoPlayFront = false,
  bool autoPlayBack = false,
}) {
  final database = db.AppDatabase(NativeDatabase.memory());
  final player = _FakeShortAudioPlayer();
  return (
    container: _container(
      dao,
      database,
      shortAudioPlayer: player,
      autoPlayFront: autoPlayFront,
      autoPlayBack: autoPlayBack,
    ),
    database: database,
    player: player,
  );
}

Future<void> _addPlayableMedia(db.AppDatabase database) {
  final now = DateTime.now();
  return database.audioItemDao.upsert(
    db.AudioItemsCompanion(
      id: const Value('audio-1'),
      name: const Value('Material'),
      audioPath: const Value('media/test.mp4'),
      addedDate: Value(now),
      updatedAt: Value(now),
    ),
  );
}

late Directory _testAppDataDirectory;

void main() {
  setUpAll(() async {
    _testAppDataDirectory = await Directory.systemTemp.createTemp(
      'echo_loop_bookmark_review_test-',
    );
    app_data_dir.appDataDirectoryOverride = _testAppDataDirectory;
  });

  tearDownAll(() async {
    app_data_dir.appDataDirectoryOverride = null;
    if (_testAppDataDirectory.existsSync()) {
      await _testAppDataDirectory.delete(recursive: true);
    }
  });

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
    expect(state.initialTotal, 1);
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
    await _addPlayableMedia(scope.database);
    await notifier.initialize([_bookmark(1)]);
    await notifier.revealBack();
    expect(
      container.read(bookmarkReviewProvider).face,
      BookmarkReviewFace.back,
    );
    expect(scope.player.stops, greaterThan(0));
  });

  test(
    'does not stop foreground engine when no legacy playback is active',
    () async {
      final scope = _testScope(_TestBookmarkDao());
      final container = scope.container;
      addTearDown(() async {
        container.dispose();
        await scope.database.close();
      });
      final foreground =
          container.read(foregroundAudioEngineProvider.notifier)
              as _RecordingForegroundAudioEngine;
      final notifier = container.read(bookmarkReviewProvider.notifier);

      await notifier.initialize([_bookmark(1)]);
      await notifier.revealBack();
      await notifier.interruptPlayback();

      expect(foreground.stopCalls, 0);
    },
  );

  test('stops foreground engine when legacy playback is active', () async {
    final scope = _testScope(_TestBookmarkDao());
    final container = scope.container;
    addTearDown(() async {
      container.dispose();
      await scope.database.close();
    });
    final foreground =
        container.read(foregroundAudioEngineProvider.notifier)
            as _RecordingForegroundAudioEngine;
    final notifier = container.read(bookmarkReviewProvider.notifier);

    foreground.isPlaying = true;
    await notifier.interruptPlayback();

    expect(foreground.stopCalls, 1);
    expect(foreground.isPlaying, isFalse);
  });

  test('shared auto-play settings control sentence front and back', () async {
    final disabled = _testScope(
      _TestBookmarkDao(),
      autoPlayFront: false,
      autoPlayBack: false,
    );
    addTearDown(() async {
      disabled.container.dispose();
      await disabled.database.close();
    });
    final disabledNotifier = disabled.container.read(
      bookmarkReviewProvider.notifier,
    );
    await disabledNotifier.initialize([_bookmark(1)]);
    await disabledNotifier.startCurrentCard();
    await disabledNotifier.revealBack();
    expect(disabled.player.rangePlays, 0);

    final enabled = _testScope(
      _TestBookmarkDao(),
      autoPlayFront: true,
      autoPlayBack: true,
    );
    addTearDown(() async {
      enabled.container.dispose();
      await enabled.database.close();
    });
    final enabledNotifier = enabled.container.read(
      bookmarkReviewProvider.notifier,
    );
    await _addPlayableMedia(enabled.database);
    await enabledNotifier.initialize([_bookmark(1)]);
    unawaited(enabledNotifier.startCurrentCard());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(enabled.player.rangePlays, 1);
    expect(enabled.player.paths.single, endsWith('media/test.mp4'));
    expect(enabled.player.ranges.single, (
      const Duration(seconds: 1),
      const Duration(seconds: 2),
    ));
    await enabledNotifier.interruptPlayback();
    await enabledNotifier.revealBack();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(enabled.player.rangePlays, 2);
    await enabledNotifier.interruptPlayback();
  });

  test('back can play and stop the current sentence', () async {
    final scope = _testScope(_TestBookmarkDao());
    final container = scope.container;
    addTearDown(() async {
      container.dispose();
      await scope.database.close();
    });
    final notifier = container.read(bookmarkReviewProvider.notifier);
    await _addPlayableMedia(scope.database);
    await notifier.initialize([_bookmark(1)]);
    await notifier.revealBack();

    final playback = notifier.toggleCurrentPlayback();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(scope.player.rangePlays, 1);
    expect(
      container.read(bookmarkReviewProvider).playbackState,
      BookmarkReviewPlaybackState.playing,
    );

    await notifier.toggleCurrentPlayback();
    expect(scope.player.stops, greaterThan(0));
    expect(
      container.read(bookmarkReviewProvider).playbackState,
      BookmarkReviewPlaybackState.idle,
    );
    await playback;
  });

  test('completed sentence playback returns to idle', () async {
    final scope = _testScope(_TestBookmarkDao());
    addTearDown(() async {
      scope.container.dispose();
      await scope.database.close();
    });
    final notifier = scope.container.read(bookmarkReviewProvider.notifier);
    await _addPlayableMedia(scope.database);
    await notifier.initialize([_bookmark(1)]);
    await notifier.revealBack();

    final playback = notifier.toggleCurrentPlayback();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    scope.player.completeRange(AudioPlaybackResult.completed);
    await playback;

    expect(
      scope.container.read(bookmarkReviewProvider).playbackState,
      BookmarkReviewPlaybackState.idle,
    );
  });

  test(
    'rating the last card stops playback before showing completion',
    () async {
      final scope = _testScope(_TestBookmarkDao(), autoPlayBack: true);
      addTearDown(() async {
        scope.container.dispose();
        await scope.database.close();
      });
      final notifier = scope.container.read(bookmarkReviewProvider.notifier);
      await _addPlayableMedia(scope.database);
      await notifier.initialize([_bookmark(1)]);
      await notifier.revealBack();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(scope.player.pendingRangePlay, isNotNull);

      await notifier.selectRating(MemoryRating.good);

      expect(scope.player.stops, greaterThan(0));
      expect(scope.container.read(bookmarkReviewProvider).currentCard, isNull);
      expect(
        scope.container.read(bookmarkReviewProvider).completionSummary,
        isNotNull,
      );
    },
  );

  test('failed sentence playback exposes the existing failed state', () async {
    final scope = _testScope(_TestBookmarkDao());
    addTearDown(() async {
      scope.container.dispose();
      await scope.database.close();
    });
    final notifier = scope.container.read(bookmarkReviewProvider.notifier);
    await _addPlayableMedia(scope.database);
    await notifier.initialize([_bookmark(1)]);
    await notifier.revealBack();

    final playback = notifier.toggleCurrentPlayback();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    scope.player.completeRange(AudioPlaybackResult.failed);
    await playback;

    final state = scope.container.read(bookmarkReviewProvider);
    expect(state.playbackState, BookmarkReviewPlaybackState.failed);
    expect(state.mediaError, 'audio_unavailable');
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
    expect(container.read(bookmarkReviewProvider).remainingCount, 1);
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
    expect(state.remainingCount, 1);
    expect(state.removeError, isNotNull);
    expect(state.isRemoving, isFalse);
  });
}
