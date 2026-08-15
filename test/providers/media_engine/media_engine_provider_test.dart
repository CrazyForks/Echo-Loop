import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:echo_loop/models/audio_item.dart';
import 'package:echo_loop/models/sentence.dart';
import 'package:echo_loop/models/sentence_playback_result.dart';
import 'package:echo_loop/providers/learning_session/intensive_listen_playback_driver.dart';
import 'package:echo_loop/providers/media_engine/media_engine_provider.dart';
import 'package:echo_loop/providers/media_engine/media_sense_group_range_playback.dart';
import 'package:echo_loop/services/media_session_router.dart';
import 'package:echo_loop/utils/app_data_dir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/shared/fake_media_player_backend.dart';

void main() {
  late FakeMediaPlayerBackend backend;
  late MediaSessionRouter router;
  late ProviderContainer container;
  late Directory appDir;
  late File mediaFile;

  setUp(() async {
    appDir = await Directory.systemTemp.createTemp('echo-loop-media-engine-');
    appDataDirectoryOverride = appDir;
    backend = FakeMediaPlayerBackend();
    router = MediaSessionRouter(defaultHandler: BaseAudioHandler());
    container = ProviderContainer(
      overrides: [
        mediaBackendFactoryProvider.overrideWithValue(() => backend),
        mediaSessionRouterProvider.overrideWithValue(router),
      ],
    );
    mediaFile = File('${appDir.path}/echo-loop-video-test.mp4');
    await mediaFile.writeAsBytes(const [0, 1, 2]);
  });

  tearDown(() async {
    container.dispose();
    appDataDirectoryOverride = null;
    if (await appDir.exists()) await appDir.delete(recursive: true);
  });

  AudioItem item() => AudioItem(
    id: 'video-1',
    name: 'Video',
    audioPath: 'echo-loop-video-test.mp4',
    addedDate: DateTime(2026, 7, 24),
  );

  test('loadMedia 成功后打开 backend 并激活媒体会话', () async {
    final engine = container.read(mediaEngineProvider.notifier);

    final duration = await engine.loadMedia(
      item(),
      1.25,
      initialPosition: const Duration(seconds: 4),
    );

    expect(duration, const Duration(seconds: 10));
    expect(backend.openCalls, [mediaFile.path]);
    expect(backend.openInitialPositions, [const Duration(seconds: 4)]);
    expect(backend.rateCalls, [1.25]);
    expect(router.isRouted, isTrue);
    expect(container.read(mediaEngineProvider).currentMediaId, 'video-1');
  });

  test('playRangeOnce 到达区间终点后自动暂停', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);
    final sid = engine.newSession();

    final playing = engine.playRangeOnce(
      const Duration(seconds: 1),
      const Duration(seconds: 3),
      sid,
    );
    await Future<void>.delayed(Duration.zero);

    expect(backend.seekCalls.last, const Duration(seconds: 1));
    expect(backend.playCalls, 1);
    backend.emitPosition(const Duration(seconds: 3));
    expect(await playing, SentencePlaybackResult.completed);

    expect(backend.pauseCalls, 1);
  });

  test('pause 会使旧区间 session 失效，旧终点不再二次暂停', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);
    final sid = engine.newSession();

    final playing = engine.playRangeOnce(
      Duration.zero,
      const Duration(seconds: 4),
      sid,
    );
    await Future<void>.delayed(Duration.zero);
    await engine.pause();
    backend.emitPosition(const Duration(seconds: 5));
    expect(await playing, SentencePlaybackResult.cancelled);

    expect(backend.pauseCalls, 1);
  });

  test('播放器提前 completed 时返回 failed，不能伪装成区间完成', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);
    final sid = engine.newSession();

    final playing = engine.playRangeOnce(
      const Duration(seconds: 1),
      const Duration(seconds: 3),
      sid,
    );
    await Future<void>.delayed(Duration.zero);
    backend.emitPosition(const Duration(seconds: 2));
    backend.emitCompleted();

    expect(await playing, SentencePlaybackResult.failed);
    expect(backend.pauseCalls, 1);
  });

  test('媒体意群播放按当前速度播放区间，取消后旧 session 不再生效', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);
    final playback = MediaSenseGroupRangePlayback(
      engine: engine,
      playbackSpeed: () => 1.25,
    );

    final playing = playback.play(
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    );
    await Future<void>.delayed(Duration.zero);
    expect(backend.rateCalls.last, 1.25);
    expect(backend.seekCalls.last, const Duration(seconds: 2));

    await playback.cancel();
    backend.emitPosition(const Duration(seconds: 4));
    await playing;

    expect(backend.pauseCalls, 1);
  });

  test('disposeChain 交还会话并释放 backend', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);

    await engine.disposeChain();

    expect(router.isRouted, isFalse);
    expect(backend.stopCalls, 1);
    expect(backend.disposed, isTrue);
  });

  test('releaseFromScreen 使 session 失效并释放 backend', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);
    final sid = engine.newSession();

    await engine.releaseFromScreen();

    expect(engine.isActiveSession(sid), isFalse);
    expect(backend.pauseCalls, 1);
    expect(backend.stopCalls, 1);
    expect(router.isRouted, isFalse);
    expect(backend.disposed, isTrue);
  });

  test('setSubtitleTrackData 加载或关闭视频字幕轨', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);

    await engine.setSubtitleTrackData('1\n00:00:00,000 --> 00:00:01,000\nHi\n');
    await engine.setSubtitleTrackData(null);

    expect(backend.subtitleTrackDataCalls, [
      '1\n00:00:00,000 --> 00:00:01,000\nHi\n',
      null,
    ]);
    expect(container.read(mediaEngineProvider).subtitleTrackEnabled, isFalse);
  });

  test('视频精听适配器按绝对句子区间播放并接管锁屏切句', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);
    final driver = MediaIntensiveListenPlaybackDriver(engine);
    final sid = driver.newSession();
    var previousCalls = 0;
    var nextCalls = 0;
    driver.bindLockScreen(
      onPlay: () async {},
      onPause: () async {},
      onPrevious: () async => previousCalls++,
      onNext: () async => nextCalls++,
    );

    final playing = driver.playSentence(
      Sentence(
        index: 0,
        text: 'hello',
        startTime: Duration(seconds: 2),
        endTime: Duration(seconds: 5),
      ),
      sid,
    );
    await Future<void>.delayed(Duration.zero);
    expect(backend.seekCalls.last, const Duration(seconds: 2));
    backend.emitPosition(const Duration(seconds: 5));
    await playing;

    await router.skipToPrevious();
    await router.skipToNext();
    expect(previousCalls, 1);
    expect(nextCalls, 1);

    driver.setSessionActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(backend.startKeepAliveCalls, 1);
    expect(router.playbackState.value.playing, isTrue);
    driver.setProgressFrozen(true);
    await Future<void>.delayed(Duration.zero);
    expect(router.playbackState.value.speed, 0);
    driver.unbindLockScreen();
    await Future<void>.delayed(Duration.zero);
    expect(backend.stopKeepAliveCalls, 1);
  });

  test('ProviderContainer dispose 时释放 backend，避免热重启残留 native 链路', () async {
    final engine = container.read(mediaEngineProvider.notifier);
    await engine.loadMedia(item(), 1.0);

    container.dispose();
    await Future<void>.delayed(Duration.zero);
    container = ProviderContainer();

    expect(router.isRouted, isFalse);
    expect(backend.stopCalls, 1);
    expect(backend.disposed, isTrue);
  });
}
