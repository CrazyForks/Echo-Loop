import '../../models/sentence.dart';
import '../audio_engine/audio_engine_provider.dart';
import '../audio_engine/foreground_audio_engine_provider.dart';
import '../media_engine/media_engine_provider.dart';

/// 句子级学习任务依赖的最小播放契约。
///
/// 学习状态机只描述“播放一句”，不关心底层是 just_audio 还是 media_kit。
/// 音频适配器继续委托原引擎，视频适配器复用同一 MediaEngine。
abstract interface class SentencePlaybackDriver {
  int newSession();
  bool isActiveSession(int sessionId);

  /// 底层是否已负责记录成功播放的学习事件。
  bool get recordsStudyEventsInternally;

  Future<void> pause();
  Future<void> setSpeed(double speed);
  Future<void> playSentence(Sentence sentence, int sessionId);

  /// 绑定系统媒体控制；不提供系统媒体会话的前台音频适配器实现为空操作。
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

/// 逐句精听在句子播放之外还需要意群区间播放。
abstract interface class IntensiveListenPlaybackDriver
    implements SentencePlaybackDriver {
  Future<void> playRangeOnce(Duration start, Duration end, int sessionId);
}

/// 难句跟读原音频适配器；所有调用仍委托前台 just_audio 引擎。
class ForegroundSentencePlaybackDriver implements SentencePlaybackDriver {
  ForegroundSentencePlaybackDriver(this._engine);

  final ForegroundAudioEngine _engine;

  @override
  bool get recordsStudyEventsInternally => true;

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

/// 原音频逐句精听适配器；所有调用仍原样委托给 AudioEngine。
class AudioIntensiveListenPlaybackDriver
    implements IntensiveListenPlaybackDriver {
  AudioIntensiveListenPlaybackDriver(this._engine);

  final AudioEngine _engine;

  @override
  bool get recordsStudyEventsInternally => true;

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

/// 学习任务共享的媒体句子播放驱动；只操作 MediaEngine，不接管音频链路。
class MediaSentencePlaybackDriver implements IntensiveListenPlaybackDriver {
  MediaSentencePlaybackDriver(this._engine);

  final MediaEngine _engine;

  @override
  bool get recordsStudyEventsInternally => false;

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

/// 旧名称兼容层；媒体句子驱动已供多个学习任务共享。
typedef MediaIntensiveListenPlaybackDriver = MediaSentencePlaybackDriver;
