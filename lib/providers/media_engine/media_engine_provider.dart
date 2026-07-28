import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/audio_item.dart';
import '../../models/media_engine_state.dart';
import '../../services/background_audio_handler.dart';
import '../../services/echo_loop_media_handler.dart';
import '../../services/app_logger.dart';
import '../../services/media_kit_player_backend.dart';
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

  @override
  MediaEngineState build() {
    ref.onDispose(() {
      unawaited(_disposeChain(resetState: false, reason: 'provider-dispose'));
    });
    return const MediaEngineState();
  }

  Future<void> ensureChain() async {
    if (_backend != null && _handler != null) return;
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
    state = state.copyWith(sessionId: state.sessionId + 1);
    await _handler?.pauseBackend();
  }

  Future<void> pauseKeepSession() async => _handler?.pauseBackend();

  Future<void> stop() async {
    state = state.copyWith(sessionId: state.sessionId + 1);
    await _handler?.stop();
  }

  /// 页面退出释放链路：只让业务 session 失效并释放 backend，不等待系统 stop 回调。
  Future<void> releaseFromScreen() async {
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

  Future<void> playRangeOnce(
    Duration start,
    Duration end,
    int sessionId,
  ) async {
    final handler = _handler;
    final backend = _backend;
    if (handler == null || backend == null || !isActiveSession(sessionId)) {
      return;
    }

    await handler.seek(start);
    if (!isActiveSession(sessionId)) return;

    final reached = _awaitRangeEndOrInvalid(backend, end, sessionId);
    await handler.playBackend();
    if (!isActiveSession(sessionId)) {
      await handler.pauseBackend();
      return;
    }

    await reached;
    if (isActiveSession(sessionId)) {
      await handler.pauseBackend();
    }
  }

  /// 等待区间终点、自然完成或 session 失效；200ms 守卫避免位置流停发时泄漏。
  Future<void> _awaitRangeEndOrInvalid(
    MediaPlayerBackend backend,
    Duration end,
    int sessionId,
  ) {
    final completer = Completer<void>();
    StreamSubscription<Duration>? posSub;
    StreamSubscription<void>? doneSub;
    Timer? guard;
    void finish() {
      if (completer.isCompleted) return;
      unawaited(posSub?.cancel());
      unawaited(doneSub?.cancel());
      guard?.cancel();
      completer.complete();
    }

    posSub = backend.positionStream.listen((pos) {
      if (pos >= end || !isActiveSession(sessionId)) finish();
    });
    doneSub = backend.completedStream.listen((_) => finish());
    guard = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!isActiveSession(sessionId) || backend.position >= end) finish();
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
