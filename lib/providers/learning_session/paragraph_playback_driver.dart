import 'dart:async';

import '../../models/sentence_playback_result.dart';
import '../audio_engine/audio_engine_provider.dart';
import '../audio_engine/foreground_audio_engine_provider.dart';
import '../media_engine/media_engine_provider.dart';

/// 段落任务的底层播放契约。
///
/// 盲听与后续复述只依赖此接口，不感知 just_audio 或 media_kit，保证音频与
/// 视频会话各自独立，同时复用同一段落状态机。
abstract interface class ParagraphPlaybackDriver {
  int newSession();
  bool isActiveSession(int sessionId);
  Stream<Duration> get positionStream;
  Future<void> pause();
  Future<void> setSpeed(double speed);
  Future<void> seek(Duration position);
  Future<SentencePlaybackResult> playRange(
    Duration start,
    Duration end,
    int sessionId, {
    required double speed,
    required void Function() onRangeReady,
  });
  void bindLockScreen({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  });
  void setSessionActive(bool active);
  void setProgressFrozen(bool frozen);
  void unbindLockScreen();
}

/// 保持既有 AudioEngine 行为的盲听适配器。
class AudioParagraphPlaybackDriver implements ParagraphPlaybackDriver {
  AudioParagraphPlaybackDriver(this._engine);
  final AudioEngine _engine;

  @override
  int newSession() => _engine.newSession();
  @override
  bool isActiveSession(int sessionId) => _engine.isActiveSession(sessionId);
  @override
  Stream<Duration> get positionStream => _engine.absolutePositionStream;
  @override
  Future<void> pause() => _engine.pauseKeepSession();
  @override
  Future<void> setSpeed(double speed) => _engine.setSpeed(speed);
  @override
  Future<void> seek(Duration position) => _engine.seekToAbsolute(position);
  @override
  Future<SentencePlaybackResult> playRange(
    Duration start,
    Duration end,
    int sessionId, {
    required double speed,
    required void Function() onRangeReady,
  }) async {
    await _engine.setSpeed(speed);
    await _engine.playRangeOnce(
      start,
      end,
      sessionId,
      onClipReady: onRangeReady,
    );
    return _engine.isActiveSession(sessionId)
        ? SentencePlaybackResult.completed
        : SentencePlaybackResult.cancelled;
  }

  @override
  void bindLockScreen({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    _engine.setTransportHandlers(onPlay: onPlay, onPause: onPause);
    _engine.setSkipHandlers(onPrevious: onPrevious, onNext: onNext);
    _engine.setSeekHandlers(onRewind: null, onFastForward: null);
  }

  @override
  void setSessionActive(bool active) {
    _engine.setLogicalPlaying(active);
    active
        ? unawaited(_engine.startKeepAlive())
        : unawaited(_engine.stopKeepAlive());
  }

  @override
  void setProgressFrozen(bool frozen) => _engine.setProgressFrozen(frozen);
  @override
  void unbindLockScreen() {
    _engine.setTransportHandlers(onPlay: null, onPause: null);
    _engine.setSkipHandlers(onPrevious: null, onNext: null);
    _engine.setSeekHandlers(onRewind: null, onFastForward: null);
    _engine.setLogicalPlaying(null);
    _engine.setProgressFrozen(false);
    unawaited(_engine.stopKeepAlive());
  }
}

/// 前台音频段落适配器，供复述等录音任务使用。
///
/// 该适配器只操作裸播放器，不注册系统媒体会话；锁屏、保活和进度冻结方法均为
/// no-op。中断播放使用 `stopPlayback`，保持复述原有的 clip 切换时序。
class ForegroundParagraphPlaybackDriver implements ParagraphPlaybackDriver {
  ForegroundParagraphPlaybackDriver(this._engine);

  final ForegroundAudioEngine _engine;

  @override
  int newSession() => _engine.newSession();

  @override
  bool isActiveSession(int sessionId) => _engine.isActiveSession(sessionId);

  @override
  Stream<Duration> get positionStream => _engine.absolutePositionStream;

  @override
  Future<void> pause() => _engine.stopPlayback();

  @override
  Future<void> setSpeed(double speed) => _engine.setSpeed(speed);

  @override
  Future<void> seek(Duration position) => _engine.seekToAbsolute(position);

  @override
  Future<SentencePlaybackResult> playRange(
    Duration start,
    Duration end,
    int sessionId, {
    required double speed,
    required void Function() onRangeReady,
  }) async {
    await _engine.setSpeed(speed);
    await _engine.playRangeOnce(
      start,
      end,
      sessionId,
      onClipReady: onRangeReady,
    );
    return _engine.isActiveSession(sessionId)
        ? SentencePlaybackResult.completed
        : SentencePlaybackResult.cancelled;
  }

  @override
  void bindLockScreen({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {}

  @override
  void setSessionActive(bool active) {}

  @override
  void setProgressFrozen(bool frozen) {}

  @override
  void unbindLockScreen() {}
}

/// MediaEngine 段落适配器，供视频盲听和后续视频复述复用。
class MediaParagraphPlaybackDriver implements ParagraphPlaybackDriver {
  MediaParagraphPlaybackDriver(this._engine);
  final MediaEngine _engine;
  @override
  int newSession() => _engine.newSession();
  @override
  bool isActiveSession(int sessionId) => _engine.isActiveSession(sessionId);
  @override
  Stream<Duration> get positionStream => _engine.positionStream;
  @override
  Future<void> pause() => _engine.cancelActiveRange(reason: 'paragraph-pause');
  @override
  Future<void> setSpeed(double speed) => _engine.setSpeed(speed);
  @override
  Future<void> seek(Duration position) => _engine.seek(position);
  @override
  Future<SentencePlaybackResult> playRange(
    Duration start,
    Duration end,
    int sessionId, {
    required double speed,
    required void Function() onRangeReady,
  }) async {
    return _engine.playRange(
      start,
      end,
      speed: speed,
      onRangeReady: onRangeReady,
      sessionId: sessionId,
    );
  }

  @override
  void bindLockScreen({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    _engine.setTransportHandlers(onPlay: onPlay, onPause: onPause);
    _engine.setSkipHandlers(onPrevious: onPrevious, onNext: onNext);
  }

  @override
  void setSessionActive(bool active) {
    _engine.setLogicalPlaying(active);
    active
        ? unawaited(_engine.startKeepAlive())
        : unawaited(_engine.stopKeepAlive());
  }

  @override
  void setProgressFrozen(bool frozen) => _engine.setProgressFrozen(frozen);
  @override
  void unbindLockScreen() {
    _engine.setTransportHandlers(onPlay: null, onPause: null);
    _engine.setSkipHandlers(onPrevious: null, onNext: null);
    _engine.setLogicalPlaying(null);
    _engine.setProgressFrozen(false);
    unawaited(_engine.stopKeepAlive());
  }
}
