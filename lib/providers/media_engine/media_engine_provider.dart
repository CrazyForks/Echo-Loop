import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/audio_item.dart';
import '../../models/media_engine_state.dart';
import '../../models/sentence_playback_result.dart';
import '../../services/background_audio_handler.dart';
import '../../services/echo_loop_media_handler.dart';
import '../../services/app_logger.dart';
import '../../services/media_kit_player_backend.dart';
import '../../services/media_kit_debug_initializer.dart';
import '../../services/media_player_backend.dart';
import '../../services/media_session_router.dart';

part 'media_engine_provider.g.dart';

/// 测试缝：真实工厂造 MediaKitPlayerBackend，测试 override 注入 fake。
@Riverpod(keepAlive: true)
MediaPlayerBackend Function() mediaBackendFactory(Ref ref) {
  return () => MediaKitPlayerBackend();
}

/// 测试缝：默认读全局 router，测试 override 成纯 Dart router。
@Riverpod(keepAlive: true)
MediaSessionRouter mediaSessionRouter(Ref ref) => echoLoopMediaSessionRouter;

@Riverpod(keepAlive: true)
class MediaEngine extends _$MediaEngine {
  MediaPlayerBackend? _backend;
  EchoLoopMediaHandler? _handler;
  MediaSessionRouter? _router;
  bool _disposingChain = false;
  int _rangeRequestId = 0;
  bool _hasActiveRangeRequest = false;
  Future<void> _rangeControlTail = Future<void>.value();

  @override
  MediaEngineState build() {
    ref.onDispose(() {
      unawaited(_disposeChain(resetState: false, reason: 'provider-dispose'));
    });
    return const MediaEngineState();
  }

  Future<void> ensureChain() async {
    if (_backend != null && _handler != null) return;
    ensureMediaKitInitialized();
    final backend = ref.read(mediaBackendFactoryProvider)();
    final handler = EchoLoopMediaHandler(backend);
    final router = ref.read(mediaSessionRouterProvider);
    _backend = backend;
    _handler = handler;
    _router = router;
    unawaited(handler.prepareArtwork());
    unawaited(handler.configureInterruptions());
  }

  Future<void> disposeChain() async {
    await _disposeChain(resetState: true, reason: 'explicit');
  }

  /// 所有者销毁时释放 native 链路，不写 provider state。
  Future<void> releaseForOwnerDispose() async {
    await _disposeChain(resetState: false, reason: 'owner-dispose');
  }

  /// 释放 media_kit 原生链路。
  ///
  /// debug hot restart 会销毁旧 Dart isolate，但旧 mpv 线程可能仍持有 FFI
  /// callback。这里在页面退出、ProviderScope 销毁等可控路径尽早卸载媒体并释放
  /// backend，减少下一次启动由 media_kit 清理旧 mpv handle 时触发旧 callback 的机会。
  Future<void> _disposeChain({
    required bool resetState,
    required String reason,
  }) async {
    if (_disposingChain) return;
    _invalidateRangeRequest('dispose-$reason');
    _disposingChain = true;
    final handler = _handler;
    final backend = _backend;
    final router = _router;
    _handler = null;
    _backend = null;
    _router = null;
    try {
      if (handler != null) {
        router?.deactivate(handler);
        await handler.dispose();
      }
      try {
        await backend?.stop();
      } catch (_) {
        // backend.dispose() 仍会尝试 stop；这里的 stop 只是提前卸载媒体的防护。
      }
      await backend?.dispose();
      if (resetState) {
        state = const MediaEngineState().copyWith(
          sessionId: state.sessionId + 1,
        );
      }
    } catch (e) {
      // 释放路径不能沉默失败；日志保留 reason 方便区分页面退出与容器销毁。
      // 不向上抛，避免 dispose 阶段异常打断 Flutter 清理流程。
      AppLogger.log('MediaEngine', '✗ disposeChain failed ($reason): $e');
    } finally {
      _disposingChain = false;
    }
  }

  Future<Duration?> loadMedia(
    AudioItem item,
    double speed, {
    Duration initialPosition = Duration.zero,
  }) async {
    await ensureChain();
    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearTotalDuration: true,
    );
    final path = await item.getFullAudioPath();
    if (path == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'file not available',
      );
      return null;
    }
    final handler = _handler;
    final backend = _backend;
    if (handler == null || backend == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'media chain not available',
      );
      return null;
    }
    try {
      handler.setNowPlaying(id: item.id, title: item.name);
      await backend.open(path, initialPosition: initialPosition);
      await backend.setRate(speed);
      _router?.activate(handler);
      final duration =
          backend.duration ??
          await backend.durationStream
              .firstWhere((value) => value > Duration.zero)
              .timeout(const Duration(seconds: 10));
      state = state.copyWith(
        totalDuration: duration,
        currentMediaId: item.id,
        isLoading: false,
      );
      return duration;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  int newSession() {
    final next = state.sessionId + 1;
    state = state.copyWith(sessionId: next);
    return next;
  }

  bool isActiveSession(int id) => id == state.sessionId;

  int get currentSessionId => state.sessionId;

  /// 已解码视频的显示方向，已由后端处理旋转元数据。
  bool? get isLandscapeVideo => _backend?.isLandscapeVideo;

  Stream<bool?> get isLandscapeVideoStream =>
      _backend?.isLandscapeVideoStream ?? const Stream<bool?>.empty();

  /// 已解码视频的实际宽高比，供 UI 按原比例布局。
  double? get videoAspectRatio => _backend?.videoAspectRatio;

  Stream<double?> get videoAspectRatioStream =>
      _backend?.videoAspectRatioStream ?? const Stream<double?>.empty();

  Future<void> play() async => _handler?.playBackend();

  Future<void> pause() async {
    _invalidateRangeRequest('legacy-pause');
    state = state.copyWith(sessionId: state.sessionId + 1);
    await _handler?.pauseBackend();
  }

  Future<void> pauseKeepSession() async => _handler?.pauseBackend();

  Future<void> stop() async {
    _invalidateRangeRequest('legacy-stop');
    state = state.copyWith(sessionId: state.sessionId + 1);
    await _handler?.stop();
  }

  /// 页面退出释放链路：只让业务 session 失效并释放 backend，不等待系统 stop 回调。
  Future<void> releaseFromScreen() async {
    _invalidateRangeRequest('screen-release');
    state = state.copyWith(sessionId: state.sessionId + 1);
    await _handler?.pauseBackend();
    await disposeChain();
  }

  Future<void> seek(Duration pos) async => _handler?.seek(pos);

  Future<void> setSpeed(double speed) async => _handler?.setSpeed(speed);

  Future<void> setVideoTrackEnabled(bool enabled) async {
    final backend = _backend;
    if (backend == null) return;
    await backend.setVideoTrackEnabled(enabled);
    state = state.copyWith(videoTrackEnabled: enabled);
  }

  Future<void> setSubtitleTrackData(String? srt) async {
    final backend = _backend;
    if (backend == null) return;
    await backend.setSubtitleTrackData(srt);
    state = state.copyWith(subtitleTrackEnabled: srt != null && srt.isNotEmpty);
  }

  bool get isPlaying => _backend?.playing ?? false;
  Duration get currentPosition => _backend?.position ?? Duration.zero;
  Duration? get totalDuration => state.totalDuration;
  Stream<Duration> get positionStream =>
      _backend?.positionStream ?? const Stream<Duration>.empty();
  Stream<bool> get playingStream =>
      _backend?.playingStream ?? const Stream<bool>.empty();

  Widget buildVideoView({required Size viewportSize}) {
    final backend = _backend;
    if (backend == null) return const SizedBox.shrink();
    return backend.buildVideoView(viewportSize: viewportSize);
  }

  void setTransportHandlers({
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
  }) {
    _handler?.setTransportHandlers(onPlay: onPlay, onPause: onPause);
  }

  void setSkipHandlers({
    Future<void> Function()? onPrevious,
    Future<void> Function()? onNext,
  }) {
    _handler?.setSkipHandlers(onPrevious: onPrevious, onNext: onNext);
  }

  void setLogicalPlaying(bool? playing) {
    _handler?.setLogicalPlaying(playing);
  }

  void setProgressFrozen(bool frozen) {
    _handler?.setProgressFrozen(frozen);
  }

  Future<void> startKeepAlive() async => _handler?.startKeepAlive();

  Future<void> stopKeepAlive() async => _handler?.stopKeepAlive();

  /// 原子替换当前区间播放；调用方不持有媒体 session。
  ///
  /// 每个请求拥有私有 generation。新的 range、取消或页面释放都会使旧请求返回
  /// [SentencePlaybackResult.cancelled]，旧请求的迟到回调不会暂停后继请求。
  Future<SentencePlaybackResult> playRange(
    Duration start,
    Duration end, {
    required double speed,
    VoidCallback? onRangeReady,
  }) async {
    if (start < Duration.zero || end <= start) {
      AppLogger.log(
        'MediaEngine Range',
        'failed: invalid-range=${start.inMilliseconds}-${end.inMilliseconds}ms',
      );
      return SentencePlaybackResult.failed;
    }

    final requestId = ++_rangeRequestId;
    _hasActiveRangeRequest = true;
    AppLogger.log(
      'MediaEngine Range',
      'request: id=$requestId range=${start.inMilliseconds}-'
          '${end.inMilliseconds}ms speed=$speed',
    );

    final setupResult = await _enqueueRangeControl(() async {
      final handler = _handler;
      final backend = _backend;
      if (handler == null || backend == null) {
        return (result: SentencePlaybackResult.cancelled, backend: backend);
      }
      if (!_isActiveRangeRequest(requestId)) {
        return (result: SentencePlaybackResult.cancelled, backend: backend);
      }
      try {
        await handler.pauseBackend();
        if (!_isActiveRangeRequest(requestId)) {
          return (result: SentencePlaybackResult.cancelled, backend: backend);
        }
        await handler.setSpeed(speed);
        if (!_isActiveRangeRequest(requestId)) {
          return (result: SentencePlaybackResult.cancelled, backend: backend);
        }
        await handler.seek(start);
        if (!_isActiveRangeRequest(requestId)) {
          return (result: SentencePlaybackResult.cancelled, backend: backend);
        }
        return (result: SentencePlaybackResult.completed, backend: backend);
      } catch (error) {
        AppLogger.log(
          'MediaEngine Range',
          'failed: id=$requestId setup-error=$error',
        );
        _invalidateRangeRequest('setup-failed');
        return (result: SentencePlaybackResult.failed, backend: backend);
      }
    });

    final backend = setupResult.backend;
    if (setupResult.result != SentencePlaybackResult.completed ||
        backend == null ||
        !_isActiveRangeRequest(requestId)) {
      return _rangeResultFor(requestId, setupResult.result);
    }

    final reached = _awaitRangeEndOrRequestInvalid(backend, end, requestId);
    final playResult = await _enqueueRangeControl(() async {
      final handler = _handler;
      if (handler == null || !_isActiveRangeRequest(requestId)) {
        return SentencePlaybackResult.cancelled;
      }
      try {
        // seek 已完成且请求仍有效，调用方此刻才能安全订阅位置流。
        onRangeReady?.call();
        await handler.playBackend();
        return _isActiveRangeRequest(requestId)
            ? SentencePlaybackResult.completed
            : SentencePlaybackResult.cancelled;
      } catch (error) {
        AppLogger.log(
          'MediaEngine Range',
          'failed: id=$requestId play-error=$error',
        );
        _invalidateRangeRequest('play-failed');
        return SentencePlaybackResult.failed;
      }
    });
    if (playResult != SentencePlaybackResult.completed) {
      return playResult;
    }

    final result = await reached;
    if (result == SentencePlaybackResult.completed) {
      await _enqueueRangeControl(() async {
        if (_isActiveRangeRequest(requestId)) {
          await _handler?.pauseBackend();
        }
      });
    }
    AppLogger.log(
      'MediaEngine Range',
      'return: id=$requestId position=${backend.position.inMilliseconds}ms '
          'result=$result',
    );
    _completeRangeRequest(requestId);
    return result;
  }

  /// 取消当前自管理区间播放，并等待底层暂停排在已发出的控制命令之后执行。
  Future<void> cancelActiveRange({String reason = 'caller-cancel'}) async {
    _invalidateRangeRequest(reason);
    await _enqueueRangeControl(() async {
      await _handler?.pauseBackend();
    });
  }

  bool _isActiveRangeRequest(int requestId) =>
      _hasActiveRangeRequest && requestId == _rangeRequestId;

  void _completeRangeRequest(int requestId) {
    if (_isActiveRangeRequest(requestId)) {
      _hasActiveRangeRequest = false;
    }
  }

  SentencePlaybackResult _rangeResultFor(
    int requestId,
    SentencePlaybackResult fallback,
  ) => _isActiveRangeRequest(requestId)
      ? fallback
      : SentencePlaybackResult.cancelled;

  void _invalidateRangeRequest(String reason) {
    if (!_hasActiveRangeRequest) return;
    final previous = _rangeRequestId;
    _rangeRequestId += 1;
    _hasActiveRangeRequest = false;
    AppLogger.log(
      'MediaEngine Range',
      'cancel: previous=$previous current=$_rangeRequestId reason=$reason',
    );
  }

  Future<T> _enqueueRangeControl<T>(Future<T> Function() operation) {
    final queued = _rangeControlTail.then((_) => operation());
    _rangeControlTail = queued.then<void>((_) {}, onError: (_, _) {});
    return queued;
  }

  Future<SentencePlaybackResult> _awaitRangeEndOrRequestInvalid(
    MediaPlayerBackend backend,
    Duration end,
    int requestId,
  ) {
    final completer = Completer<SentencePlaybackResult>();
    StreamSubscription<Duration>? posSub;
    StreamSubscription<void>? doneSub;
    Timer? guard;
    void finish(SentencePlaybackResult result) {
      if (completer.isCompleted) return;
      unawaited(posSub?.cancel());
      unawaited(doneSub?.cancel());
      guard?.cancel();
      completer.complete(result);
    }

    posSub = backend.positionStream.listen((position) {
      if (!_isActiveRangeRequest(requestId)) {
        finish(SentencePlaybackResult.cancelled);
      } else if (position >= end) {
        finish(SentencePlaybackResult.completed);
      }
    });
    doneSub = backend.completedStream.listen((_) {
      if (!_isActiveRangeRequest(requestId)) {
        finish(SentencePlaybackResult.cancelled);
      } else {
        finish(
          backend.position >= end
              ? SentencePlaybackResult.completed
              : SentencePlaybackResult.failed,
        );
      }
    });
    guard = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_isActiveRangeRequest(requestId)) {
        finish(SentencePlaybackResult.cancelled);
      } else if (backend.position >= end) {
        finish(SentencePlaybackResult.completed);
      }
    });
    return completer.future;
  }

  Future<void> playToEnd(int sessionId) async {
    final handler = _handler;
    final backend = _backend;
    if (handler == null || backend == null || !isActiveSession(sessionId)) {
      return;
    }

    final done = _awaitCompletedOrInvalid(backend, sessionId);
    await handler.playBackend();
    if (!isActiveSession(sessionId)) {
      await handler.pauseBackend();
    }
    await done;
  }

  Future<void> _awaitCompletedOrInvalid(
    MediaPlayerBackend backend,
    int sessionId,
  ) {
    final completer = Completer<void>();
    StreamSubscription<void>? doneSub;
    Timer? guard;
    void finish() {
      if (completer.isCompleted) return;
      unawaited(doneSub?.cancel());
      guard?.cancel();
      completer.complete();
    }

    doneSub = backend.completedStream.listen((_) => finish());
    guard = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!isActiveSession(sessionId)) finish();
    });
    return completer.future;
  }
}
