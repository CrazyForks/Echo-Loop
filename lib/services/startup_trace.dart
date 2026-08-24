/// 冷启动时序追踪。
///
/// 该服务只记录观测日志：不持有业务状态、不改变 Future 的完成顺序，也不会吞掉
/// 原调用方应当处理的异常。日志 sink 尚未就绪时先缓冲，确保导出的 app.log 能包含
/// Dart 入口到首帧之间的完整时间线。
library;

import 'dart:async';

import 'app_logger.dart';

typedef StartupTraceLogger = void Function(String tag, String message);

StartupTrace? _activeStartupTrace;

/// 注册当前进程的启动追踪器，供首帧链路上的 UI 节点追加同一条时间线。
void registerStartupTrace(StartupTrace trace) {
  _activeStartupTrace = trace;
}

/// 当前进程的启动追踪器；测试或嵌入场景未注册时返回 `null`。
StartupTrace? get activeStartupTrace => _activeStartupTrace;

/// 单次进程启动的结构化时序日志记录器。
class StartupTrace {
  StartupTrace({
    String? launchId,
    Stopwatch? stopwatch,
    int Function()? elapsedMilliseconds,
    int Function()? recordedAtMilliseconds,
    StartupTraceLogger? logger,
  }) : _launchId = launchId ?? DateTime.now().microsecondsSinceEpoch.toString(),
       _stopwatch = stopwatch ?? Stopwatch()
         ..start(),
       _elapsedMilliseconds = elapsedMilliseconds,
       _recordedAtMilliseconds =
           recordedAtMilliseconds ??
           (() => DateTime.now().millisecondsSinceEpoch),
       _logger = logger ?? AppLogger.log;

  final String _launchId;
  final Stopwatch _stopwatch;
  final int Function()? _elapsedMilliseconds;
  final int Function() _recordedAtMilliseconds;
  final StartupTraceLogger _logger;
  final List<String> _bufferedMessages = <String>[];
  bool _isAttached = false;

  /// 当前进程的启动标识，用于从累计日志中筛选同一次冷启动。
  String get launchId => _launchId;

  int get _elapsedMs =>
      _elapsedMilliseconds?.call() ?? _stopwatch.elapsedMilliseconds;

  /// 将此前缓冲的早期事件写入 [AppLogger]；重复调用不会重复落盘。
  void attachLogger() {
    if (_isAttached) return;
    _isAttached = true;
    for (final message in _bufferedMessages) {
      _logger('Startup', message);
    }
    _bufferedMessages.clear();
  }

  /// 记录单个启动事件。
  void mark(String event, {Map<String, Object?> fields = const {}}) {
    _emit(_format(event: event, fields: fields));
  }

  /// 追踪同步步骤。异常会记录后原样抛出。
  T runSync<T>(String step, T Function() operation) {
    mark('step_start', fields: {'step': step});
    final startedAt = _elapsedMs;
    try {
      final result = operation();
      mark(
        'step_success',
        fields: {'step': step, 'durationMs': _elapsedMs - startedAt},
      );
      return result;
    } catch (error, stackTrace) {
      _recordFailure(step, startedAt, error, stackTrace);
      rethrow;
    }
  }

  /// 追踪异步步骤。异常会记录后原样抛出。
  Future<T> run<T>(String step, Future<T> Function() operation) async {
    mark('step_start', fields: {'step': step});
    final startedAt = _elapsedMs;
    try {
      final result = await operation();
      mark(
        'step_success',
        fields: {'step': step, 'durationMs': _elapsedMs - startedAt},
      );
      return result;
    } catch (error, stackTrace) {
      _recordFailure(step, startedAt, error, stackTrace);
      rethrow;
    }
  }

  /// 记录不阻塞启动的任务。调用方仍负责原有异常处理语义。
  void trackDetached(String step, Future<void> future) {
    mark('detached_scheduled', fields: {'step': step});
    unawaited(
      future.then<void>(
        (_) => mark('detached_success', fields: {'step': step}),
        onError: (Object error, StackTrace stackTrace) {
          _recordFailure(step, _elapsedMs, error, stackTrace);
        },
      ),
    );
  }

  void _recordFailure(
    String step,
    int startedAt,
    Object error,
    StackTrace stackTrace,
  ) {
    mark(
      'step_failure',
      fields: {
        'step': step,
        'durationMs': _elapsedMs - startedAt,
        'errorType': error.runtimeType,
        'error': _singleLine(error.toString()),
      },
    );
    mark(
      'step_failure_stack',
      fields: {'step': step, 'stack': _singleLine(stackTrace.toString())},
    );
  }

  void _emit(String message) {
    if (_isAttached) {
      _logger('Startup', message);
      return;
    }
    _bufferedMessages.add(message);
  }

  String _format({
    required String event,
    required Map<String, Object?> fields,
  }) {
    final parts = <String>[
      'event=$event',
      'launchId=$_launchId',
      // AppLogger 的行前缀代表日志实际写入时刻。启动早期事件会被缓冲，
      // 因此必须保存采样时刻，才能与单调 elapsedMs 一起正确还原时序。
      'recordedAtMs=${_recordedAtMilliseconds()}',
      'elapsedMs=$_elapsedMs',
      ...fields.entries.map(
        (entry) => '${entry.key}=${_singleLine('${entry.value}')}',
      ),
    ];
    return parts.join(' ');
  }

  String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' \\n ');
}
