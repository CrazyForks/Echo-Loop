import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/study_stage.dart';
import 'app_logger.dart';
import 'study_time_service.dart';

/// 统计一个前台有效学习会话，并以增量方式定期落库。
///
/// 计时器只负责会话生命周期和可靠落库，具体数据库写入统一委托给
/// [StudyTimeService]。后台、隐藏和锁屏期间不会计入学习时长。
final class StudySessionTimer {
  StudySessionTimer({
    required StudyTimeService studyTimeService,
    required StudyStage stage,
    this.checkpointInterval = const Duration(seconds: 30),
    String? logScope,
  }) : _studyTimeService = studyTimeService,
       _stage = stage,
       _logScope = logScope ?? 'StudySessionTimer' {
    if (checkpointInterval <= Duration.zero) {
      throw ArgumentError.value(
        checkpointInterval,
        'checkpointInterval',
        '必须大于 0。',
      );
    }
    _lifecycleListener = AppLifecycleListener(onStateChange: _onLifecycleState);
  }

  final StudyTimeService _studyTimeService;
  final StudyStage _stage;
  final Duration checkpointInterval;
  final String _logScope;
  final Stopwatch _stopwatch = Stopwatch();
  late final AppLifecycleListener _lifecycleListener;
  Timer? _checkpointTimer;
  Future<void>? _flushOperation;
  int _persistedMilliseconds = 0;
  bool _started = false;
  bool _stopped = false;

  /// 当前会话累计的前台有效时长。
  Duration get elapsed => _stopwatch.elapsed;

  /// 启动当前会话；重复调用不会重置已累计时长。
  void start() {
    if (_stopped || _started) return;
    _started = true;
    _stopwatch.start();
    _checkpointTimer = Timer.periodic(checkpointInterval, (_) {
      unawaited(flush());
    });
    AppLogger.log(_logScope, 'session.start stage=${_stage.name}');
  }

  /// 暂停前台计时，并立即尝试落库。
  Future<void> pause() async {
    if (!_started || _stopped) return;
    _stopwatch.stop();
    AppLogger.log(
      _logScope,
      'session.pause stage=${_stage.name} elapsedMs=${_stopwatch.elapsedMilliseconds}',
    );
    await flush();
  }

  /// 恢复前台计时。
  void resume() {
    if (!_started || _stopped || _stopwatch.isRunning) return;
    _stopwatch.start();
    AppLogger.log(_logScope, 'session.resume stage=${_stage.name}');
  }

  /// 只落库尚未持久化的有效时长。
  Future<void> flush() {
    final active = _flushOperation;
    if (active != null) return active;
    final operation = _flushIncrement();
    _flushOperation = operation;
    return operation.whenComplete(() => _flushOperation = null);
  }

  Future<void> _flushIncrement() async {
    final elapsedMilliseconds = _stopwatch.elapsedMilliseconds;
    final pendingMilliseconds = elapsedMilliseconds - _persistedMilliseconds;
    final pendingSeconds = pendingMilliseconds ~/ 1000;
    if (pendingSeconds <= 0) return;
    final persistedMilliseconds = pendingSeconds * 1000;
    try {
      await _studyTimeService.addStudyTime(
        persistedMilliseconds ~/ 1000,
        stage: _stage,
      );
      _persistedMilliseconds += persistedMilliseconds;
      AppLogger.log(
        _logScope,
        'session.flush stage=${_stage.name} seconds=$pendingSeconds totalMs=$elapsedMilliseconds',
      );
    } catch (error, stackTrace) {
      AppLogger.log(
        _logScope,
        'session.flush.failed stage=${_stage.name} error=$error\n$stackTrace',
      );
    }
  }

  /// 停止会话、最终落库并释放资源。
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _stopwatch.stop();
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    await flush();
    AppLogger.log(
      _logScope,
      'session.stop stage=${_stage.name} totalMs=${_stopwatch.elapsedMilliseconds}',
    );
  }

  /// stop 的资源释放别名，便于 Provider 销毁时安全调用。
  Future<void> dispose() async {
    await stop();
    _lifecycleListener.dispose();
  }

  void _onLifecycleState(AppLifecycleState state) {
    if (!_started || _stopped) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        unawaited(pause());
      case AppLifecycleState.resumed:
        resume();
    }
  }
}
