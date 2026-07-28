import '../../models/sentence.dart';
import '../audio_engine/audio_engine_provider.dart';
import '../media_engine/media_engine_provider.dart';

/// 逐句精听依赖的最小播放契约。
///
/// 学习状态机只描述“播放某个时间区间”，不关心底层是 just_audio 还是
/// media_kit。这样音频继续使用原链路，视频可以独立迁移到 MediaEngine。
abstract interface class IntensiveListenPlaybackDriver {
  int newSession();
  bool isActiveSession(int sessionId);

  Future<void> pause();
  Future<void> setSpeed(double speed);
  Future<void> playSentence(Sentence sentence, int sessionId);
  Future<void> playRangeOnce(Duration start, Duration end, int sessionId);

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

/// 原音频逐句精听适配器；所有调用仍原样委托给 AudioEngine。
class AudioIntensiveListenPlaybackDriver
    implements IntensiveListenPlaybackDriver {
  AudioIntensiveListenPlaybackDriver(this._engine);

  final AudioEngine _engine;

  @override
  int newSession() => _engine.newSession();

  @override
  bool isActiveSession(int sessionId) => _engine.isActiveSession(sessionId);

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> setSpeed(double speed) => _engine.setSpeed(speed);

  @override
  Future<void> playSentence(Sentence sentence, int sessionId) =>
      _engine.playClipOnce(sentence, sessionId);

  @override
  Future<void> playRangeOnce(Duration start, Duration end, int sessionId) =>
      _engine.playRangeOnce(start, end, sessionId);

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
    if (active) {
      _engine.startKeepAlive();
    } else {
      _engine.stopKeepAlive();
    }
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
    _engine.stopKeepAlive();
  }
}

/// 视频逐句精听适配器；只驱动 media_kit 的 MediaEngine 链路。
class MediaIntensiveListenPlaybackDriver
    implements IntensiveListenPlaybackDriver {
  MediaIntensiveListenPlaybackDriver(this._engine);

  final MediaEngine _engine;

  @override
  int newSession() => _engine.newSession();

  @override
  bool isActiveSession(int sessionId) => _engine.isActiveSession(sessionId);

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> setSpeed(double speed) => _engine.setSpeed(speed);

  @override
  Future<void> playSentence(Sentence sentence, int sessionId) =>
      _engine.playRangeOnce(sentence.startTime, sentence.endTime, sessionId);

  @override
  Future<void> playRangeOnce(Duration start, Duration end, int sessionId) =>
      _engine.playRangeOnce(start, end, sessionId);

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
    if (active) {
      _engine.startKeepAlive();
    } else {
      _engine.stopKeepAlive();
    }
  }

  @override
  void setProgressFrozen(bool frozen) => _engine.setProgressFrozen(frozen);

  @override
  void unbindLockScreen() {
    _engine.setTransportHandlers(onPlay: null, onPause: null);
    _engine.setSkipHandlers(onPrevious: null, onNext: null);
    _engine.setLogicalPlaying(null);
    _engine.setProgressFrozen(false);
    _engine.stopKeepAlive();
  }
}
