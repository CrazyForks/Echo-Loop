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

  /// 播放文件直到完成。新播放或 stop 会使旧 await 失效。
  Future<bool> playFile(String filePath) async {
    final sessionId = ++_sessionId;
    final completion = _replaceActivePlayback();
    try {
      await _backend.stop();
      if (sessionId != _sessionId) return false;
      AppLogger.log(
        'PronunciationPlayer',
        '▶ open sid=$sessionId path=$filePath',
      );
      // open(play: true) may emit completion/error immediately.
      _watchCompletion(completion, sessionId);
      await _backend.open(filePath);
      if (sessionId != _sessionId) return false;
      return await completion.future;
    } catch (error, stackTrace) {
      completion.finish(false);
      AppLogger.log(
        'PronunciationPlayer',
        'play failed path=$filePath error=$error\n$stackTrace',
      );
      return false;
    } finally {
      if (identical(_activePlayback, completion)) _activePlayback = null;
    }
  }

  /// 播放本地文件的指定时间区间；新播放或停止会立即使本次等待返回 false。
  ///
  /// media_kit 没有区间终点参数，因此以位置流和 200ms 兜底共同检测终点。
  Future<bool> playRangeFile(
    String filePath, {
    required Duration start,
    required Duration end,
  }) async {
    if (start < Duration.zero || end <= start) return false;
    final sessionId = ++_sessionId;
    final completion = _replaceActivePlayback();
    StreamSubscription<Duration>? positionSub;
    Timer? guard;

    void stopAtEnd() {
      if (sessionId != _sessionId) return;
      completion.finish(true);
      unawaited(_backend.stop());
    }

    try {
      await _backend.stop();
      if (sessionId != _sessionId) return false;
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
          completion.finish(false);
        } else if (_backend.position >= end) {
          stopAtEnd();
        }
      });
      // Register completion/error/position listeners before playback starts.
      _watchCompletion(completion, sessionId);
      await _backend.open(filePath, start: start);
      if (sessionId != _sessionId) return false;
      if (_backend.position >= end) stopAtEnd();
      return await completion.future;
    } catch (error, stackTrace) {
      completion.finish(false);
      AppLogger.log(
        'PronunciationPlayer',
        'range play failed path=$filePath error=$error\n$stackTrace',
      );
      return false;
    } finally {
      await positionSub?.cancel();
      guard?.cancel();
      if (identical(_activePlayback, completion)) _activePlayback = null;
    }
  }

  _PlaybackCompletion _replaceActivePlayback() {
    _activePlayback?.finish(false);
    final completion = _PlaybackCompletion();
    _activePlayback = completion;
    return completion;
  }

  void _watchCompletion(_PlaybackCompletion completion, int sessionId) {
    late final StreamSubscription<void> completedSub;
    late final StreamSubscription<String> errorSub;
    void finish(bool result) {
      if (sessionId == _sessionId) completion.finish(result);
    }

    completedSub = _backend.completed.listen((_) => finish(true));
    errorSub = _backend.errors.listen((message) {
      AppLogger.log('PronunciationPlayer', '播放解码失败: $message');
      finish(false);
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
    _activePlayback?.finish(false);
    _activePlayback = null;
    await _backend.stop();
  }

  Future<void> dispose() async {
    _sessionId++;
    _activePlayback?.finish(false);
    _activePlayback = null;
    await _backend.dispose();
  }
}

class _PlaybackCompletion {
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get future => _completer.future;

  void finish(bool result) {
    if (!_completer.isCompleted) _completer.complete(result);
  }
}
