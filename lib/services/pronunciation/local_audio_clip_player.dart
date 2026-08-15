import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../app_logger.dart';

/// 无画面短音频播放器后端，测试可注入 fake。
///
/// 视频文件也仅选择并播放其音轨，不创建视频纹理或提供视频 UI。
abstract interface class PronunciationPlayerBackend {
  Stream<void> get completed;
  Stream<String> get errors;
  Stream<Duration> get positions;
  Duration get position;
  Future<void> open(String filePath, {Duration start = Duration.zero});
  Future<void> stop();
  Future<void> dispose();
}

/// native media backend 不可用时的降级实现（例如未打包 Mpv 的单测环境）。
///
/// 该后端不伪造播放成功，只让调用方收到失败结果并继续既有回退链路。
class UnavailablePronunciationPlayerBackend
    implements PronunciationPlayerBackend {
  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get errors =>
      Stream<String>.value('native backend unavailable');

  @override
  Stream<Duration> get positions => const Stream<Duration>.empty();

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> open(String filePath, {Duration start = Duration.zero}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// 基于 media_kit 的无画面音轨播放后端。
///
/// 未附加 [VideoController] 时，media_kit 原生播放器会禁用视频轨解码；
/// 因此此后端可试听视频文件中的音轨，但不能用于需要画面的视频片段。
class MediaKitPronunciationPlayerBackend implements PronunciationPlayerBackend {
  MediaKitPronunciationPlayerBackend() : _player = Player();
  final Player _player;

  @override
  Stream<void> get completed =>
      _player.stream.completed.where((value) => value).map((_) {});

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Stream<Duration> get positions => _player.stream.position;

  @override
  Duration get position => _player.state.position;

  @override
  Future<void> open(String filePath, {Duration start = Duration.zero}) =>
      _player.open(
        Media(filePath, start: start > Duration.zero ? start : null),
        play: true,
      );

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// 单次本地短音频播放的终态。
///
/// [cancelled] 表示请求被后续播放、显式停止或销毁抢占；它不是文件或解码失败，
/// 调用方不得据此触发业务回退。
enum AudioPlaybackResult { completed, cancelled, failed }

/// 共享短音频播放器的只读运行状态。
///
/// [playingKey] 是调用方提供的透明 UI 标识，播放器不解释其业务含义。
class LocalAudioClipPlaybackState {
  const LocalAudioClipPlaybackState({this.playingKey});

  final String? playingKey;
}

/// 调用方无状态的本地短音频试听服务。
///
/// 适用于单词发音、TTS 缓存及来源句等无画面的音轨播放。传入视频文件时
/// 只播放其音轨，且可在后台继续播放；需要视频画面、全屏或字幕 UI 时，应使用
/// 前台 [MediaKitPlayerBackend] 和媒体呈现宿主，而不是此服务。
class LocalAudioClipPlayer {
  LocalAudioClipPlayer({PronunciationPlayerBackend? backend})
    : _backend = backend ?? _createDefaultBackend();

  static PronunciationPlayerBackend _createDefaultBackend() {
    try {
      return MediaKitPronunciationPlayerBackend();
    } catch (error, stackTrace) {
      AppLogger.log(
        'PronunciationPlayer',
        'native backend unavailable; using failed-playback fallback: '
            '$error\n$stackTrace',
      );
      return UnavailablePronunciationPlayerBackend();
    }
  }

  final PronunciationPlayerBackend _backend;
  int _sessionId = 0;
  _PlaybackCompletion? _activePlayback;
  LocalAudioClipPlaybackState _state = const LocalAudioClipPlaybackState();
  final StreamController<LocalAudioClipPlaybackState> _states =
      StreamController<LocalAudioClipPlaybackState>.broadcast();

  LocalAudioClipPlaybackState get state => _state;
  Stream<LocalAudioClipPlaybackState> get states => _states.stream;

  /// 播放文件直到完成。新播放或 [stop] 会使旧请求返回 [AudioPlaybackResult.cancelled]。
  Future<AudioPlaybackResult> playFile(
    String filePath, {
    String? playbackKey,
  }) async {
    final sessionId = ++_sessionId;
    final completion = _replaceActivePlayback();
    _setState(LocalAudioClipPlaybackState(playingKey: playbackKey));
    try {
      await _backend.stop();
      if (sessionId != _sessionId) return AudioPlaybackResult.cancelled;
      AppLogger.log(
        'PronunciationPlayer',
        '▶ open sid=$sessionId path=$filePath',
      );
      _watchCompletion(completion, sessionId);
      await _backend.open(filePath);
      if (sessionId != _sessionId) return AudioPlaybackResult.cancelled;
      return await completion.future;
    } catch (error, stackTrace) {
      final result = sessionId == _sessionId
          ? AudioPlaybackResult.failed
          : AudioPlaybackResult.cancelled;
      completion.finish(result);
      AppLogger.log(
        'PronunciationPlayer',
        'play failed path=$filePath error=$error\n$stackTrace',
      );
      return result;
    } finally {
      _finishActivePlayback(completion);
    }
  }

  /// 播放本地文件的指定时间区间。
  ///
  /// media_kit 没有区间终点参数，因此以位置流和 200ms 兜底共同检测终点。
  Future<AudioPlaybackResult> playRangeFile(
    String filePath, {
    required Duration start,
    required Duration end,
    String? playbackKey,
  }) async {
    if (start < Duration.zero || end <= start) {
      return AudioPlaybackResult.failed;
    }
    final sessionId = ++_sessionId;
    final completion = _replaceActivePlayback();
    _setState(LocalAudioClipPlaybackState(playingKey: playbackKey));
    StreamSubscription<Duration>? positionSub;
    Timer? guard;

    void stopAtEnd() {
      if (sessionId != _sessionId) return;
      completion.finish(AudioPlaybackResult.completed);
      unawaited(_backend.stop());
    }

    try {
      await _backend.stop();
      if (sessionId != _sessionId) return AudioPlaybackResult.cancelled;
      AppLogger.log(
        'PronunciationPlayer',
        '▶ open range sid=$sessionId path=$filePath '
            'start=${start.inMilliseconds} end=${end.inMilliseconds}',
      );
      positionSub = _backend.positions.listen((position) {
        if (position >= end) stopAtEnd();
      });
      guard = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (sessionId != _sessionId) {
          completion.finish(AudioPlaybackResult.cancelled);
        } else if (_backend.position >= end) {
          stopAtEnd();
        }
      });
      _watchCompletion(completion, sessionId);
      await _backend.open(filePath, start: start);
      if (sessionId != _sessionId) return AudioPlaybackResult.cancelled;
      if (_backend.position >= end) stopAtEnd();
      return await completion.future;
    } catch (error, stackTrace) {
      final result = sessionId == _sessionId
          ? AudioPlaybackResult.failed
          : AudioPlaybackResult.cancelled;
      completion.finish(result);
      AppLogger.log(
        'PronunciationPlayer',
        'range play failed path=$filePath error=$error\n$stackTrace',
      );
      return result;
    } finally {
      await positionSub?.cancel();
      guard?.cancel();
      _finishActivePlayback(completion);
    }
  }

  _PlaybackCompletion _replaceActivePlayback() {
    _activePlayback?.finish(AudioPlaybackResult.cancelled);
    final completion = _PlaybackCompletion();
    _activePlayback = completion;
    return completion;
  }

  void _finishActivePlayback(_PlaybackCompletion completion) {
    if (!identical(_activePlayback, completion)) return;
    _activePlayback = null;
    _setState(const LocalAudioClipPlaybackState());
  }

  void _watchCompletion(_PlaybackCompletion completion, int sessionId) {
    late final StreamSubscription<void> completedSub;
    late final StreamSubscription<String> errorSub;
    void finish(AudioPlaybackResult result) {
      if (sessionId == _sessionId) completion.finish(result);
    }

    completedSub = _backend.completed.listen(
      (_) => finish(AudioPlaybackResult.completed),
    );
    errorSub = _backend.errors.listen((message) {
      AppLogger.log('PronunciationPlayer', '播放解码失败: $message');
      finish(AudioPlaybackResult.failed);
    });
    unawaited(
      completion.future.whenComplete(() async {
        await completedSub.cancel();
        await errorSub.cancel();
      }),
    );
  }

  Future<void> stop() async {
    _sessionId++;
    _activePlayback?.finish(AudioPlaybackResult.cancelled);
    _activePlayback = null;
    _setState(const LocalAudioClipPlaybackState());
    await _backend.stop();
  }

  Future<void> dispose() async {
    _sessionId++;
    _activePlayback?.finish(AudioPlaybackResult.cancelled);
    _activePlayback = null;
    _setState(const LocalAudioClipPlaybackState());
    await _backend.dispose();
    await _states.close();
  }

  void _setState(LocalAudioClipPlaybackState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}

class _PlaybackCompletion {
  final Completer<AudioPlaybackResult> _completer =
      Completer<AudioPlaybackResult>();

  Future<AudioPlaybackResult> get future => _completer.future;

  void finish(AudioPlaybackResult result) {
    if (!_completer.isCompleted) _completer.complete(result);
  }
}
