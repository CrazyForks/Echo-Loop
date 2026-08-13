import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../app_logger.dart';

/// 短音频播放器后端，测试可注入 fake。
abstract interface class PronunciationPlayerBackend {
  Stream<void> get completed;
  Stream<String> get errors;
  Stream<Duration> get positions;
  Duration get position;
  Future<void> open(String filePath, {Duration start = Duration.zero});
  Future<void> stop();
  Future<void> dispose();
}

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

/// 调用方无状态的本地发音播放服务。
class LocalPronunciationPlayer {
  LocalPronunciationPlayer({PronunciationPlayerBackend? backend})
    : _backend = backend ?? MediaKitPronunciationPlayerBackend();

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
