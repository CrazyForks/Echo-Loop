/// Echo Loop TTS（Kokoro）模型下载状态机 Provider（多变体）。
///
/// 管理 fp32 / int8 两个 Kokoro 模型变体各自的下载/重试/取消/删除与就绪状态。
/// 每个变体一个 [KokoroModelManager]（`kokoroModelManagerProvider` 的 family），
/// 互不干扰、可独立下载与删除。引擎实际使用哪个变体由 [ttsSettingsProvider] 的
/// `kokoroVariant` 决定，[kokoroReadyProvider] 即「当前选中变体是否就绪」。
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/app_logger.dart';
import '../../services/download/download_failure.dart';
import '../../services/reliable_http_downloader.dart';
import '../../services/tts/kokoro_model_manager.dart';
import 'tts_settings_provider.dart';

/// 每变体「已下载」持久化标记 key。
String _downloadedKey(KokoroModelVariant v) =>
    'kokoro_model_downloaded_${v.name}';

/// 由持久化标记 + 本地体积派生下载状态。
AsrModelDownloadStatus _deriveStatus({
  required bool fullyDownloaded,
  required int localSizeBytes,
}) {
  if (fullyDownloaded) return AsrModelDownloadStatus.downloaded;
  if (localSizeBytes > 0) return AsrModelDownloadStatus.failed;
  return AsrModelDownloadStatus.notDownloaded;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// 单个 Kokoro 模型变体的 UI 状态。
class KokoroModelState {
  final AsrModelDownloadStatus downloadStatus;
  final double downloadProgress;
  final int localSizeBytes;

  /// 失败时的归类原因（供 UI 显本地化文案）；非失败态为 null。
  final DownloadFailureKind? downloadError;

  const KokoroModelState({
    this.downloadStatus = AsrModelDownloadStatus.notDownloaded,
    this.downloadProgress = 0,
    this.localSizeBytes = 0,
    this.downloadError,
  });

  /// 模型是否已就绪（可被引擎使用）。
  bool get isReady => downloadStatus == AsrModelDownloadStatus.downloaded;

  /// 是否正在下载。
  bool get isDownloading =>
      downloadStatus == AsrModelDownloadStatus.downloading;

  KokoroModelState copyWith({
    AsrModelDownloadStatus? downloadStatus,
    double? downloadProgress,
    int? localSizeBytes,
    DownloadFailureKind? downloadError,
    bool clearError = false,
  }) {
    return KokoroModelState(
      downloadStatus: downloadStatus ?? this.downloadStatus,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      localSizeBytes: localSizeBytes ?? this.localSizeBytes,
      downloadError: clearError ? null : (downloadError ?? this.downloadError),
    );
  }
}

/// 两个变体合并的状态容器。
class KokoroModelsState {
  final Map<KokoroModelVariant, KokoroModelState> byVariant;

  const KokoroModelsState(this.byVariant);

  /// 全部未下载的初始态。
  factory KokoroModelsState.initial() => const KokoroModelsState({});

  /// 取某变体状态（缺省为未下载）。
  KokoroModelState of(KokoroModelVariant v) =>
      byVariant[v] ?? const KokoroModelState();

  /// 返回替换了某变体状态的新容器。
  KokoroModelsState withVariant(KokoroModelVariant v, KokoroModelState s) {
    return KokoroModelsState({...byVariant, v: s});
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Kokoro 模型管理器（按变体的 family，各自绑定规格）。
final kokoroModelManagerProvider =
    Provider.family<KokoroModelManager, KokoroModelVariant>((ref, variant) {
      final manager = KokoroModelManager(spec: kokoroSpecOf(variant));
      ref.onDispose(manager.dispose);
      return manager;
    });

/// 启动期注入的初始状态（main() override；缺省为全未下载）。
final initialKokoroModelStateProvider = Provider<KokoroModelsState>(
  (ref) => KokoroModelsState.initial(),
);

/// Kokoro 模型状态 Provider（keepAlive，全局单例）。
final kokoroModelProvider =
    NotifierProvider<KokoroModelNotifier, KokoroModelsState>(
      KokoroModelNotifier.new,
    );

/// 当前**选中变体**是否就绪（供控制器决定有效引擎）。
final kokoroReadyProvider = Provider<bool>((ref) {
  final variant = ref.watch(ttsSettingsProvider.select((s) => s.kokoroVariant));
  return ref.watch(kokoroModelProvider).of(variant).isReady;
});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class KokoroModelNotifier extends Notifier<KokoroModelsState> {
  final Map<KokoroModelVariant, CancelToken> _cancelTokens = {};
  final Map<KokoroModelVariant, Future<void>> _downloadTasks = {};
  final Map<KokoroModelVariant, int> _downloadSessions = {};
  final Set<KokoroModelVariant> _cancellingVariants = {};
  int _nextDownloadSession = 0;

  @override
  KokoroModelsState build() {
    ref.onDispose(() {
      for (final t in _cancelTokens.values) {
        t.cancel();
      }
    });
    return ref.read(initialKokoroModelStateProvider);
  }

  void _set(KokoroModelVariant v, KokoroModelState s) {
    state = state.withVariant(v, s);
  }

  /// 确保某变体就绪：未就绪且未在下载则触发下载。
  Future<void> ensureDownloaded(KokoroModelVariant variant) async {
    final s = state.of(variant);
    if (s.isReady ||
        s.isDownloading ||
        s.downloadStatus == AsrModelDownloadStatus.failed ||
        _cancellingVariants.contains(variant)) {
      return;
    }
    await _download(variant);
  }

  /// 重试下载（清除错误后重新下载）。
  Future<void> retryDownload(KokoroModelVariant variant) async {
    _set(variant, state.of(variant).copyWith(clearError: true));
    await _download(variant);
  }

  /// 取消某变体正在进行的下载。
  Future<void> cancelDownload(KokoroModelVariant variant) async {
    final task = _downloadTasks[variant];
    final session = _downloadSessions.remove(variant);
    _cancelTokens.remove(variant)?.cancel();
    if (session == null) return;
    _cancellingVariants.add(variant);
    // UI 立即回到未下载，取消入口不必等待下载器释放归档句柄。
    _set(
      variant,
      const KokoroModelState(
        downloadStatus: AsrModelDownloadStatus.notDownloaded,
      ),
    );
    await _persistDownloaded(variant, false);
    // 先使旧会话失效并等待下载器退出；否则旧回调或仍打开的归档文件会把取消
    // 误写成失败，或与随后删除目录发生竞争。
    try {
      await task;
      final manager = ref.read(kokoroModelManagerProvider(variant));
      await manager.deleteModel();
    } finally {
      _cancellingVariants.remove(variant);
    }
  }

  /// 删除某变体本地模型。
  Future<void> deleteModel(KokoroModelVariant variant) async {
    final manager = ref.read(kokoroModelManagerProvider(variant));
    await manager.deleteModel();
    _set(
      variant,
      const KokoroModelState(
        downloadStatus: AsrModelDownloadStatus.notDownloaded,
      ),
    );
    await _persistDownloaded(variant, false);
  }

  Future<void> _download(KokoroModelVariant variant) async {
    // 先**同步**置为下载中，再做任何 await——否则 ensureDownloaded 的「未在下载」
    // 判定与此处状态翻转之间隔着 _persistDownloaded 的 await（SP I/O）窗口，期间
    // 第二个 ensureDownloaded（如控制器自愈 + 设置页 postFrame 同帧触发）会漏过
    // 判定再起一个下载，两路下载写同一临时文件、回调交错 → 进度条来回跳。
    _set(
      variant,
      state
          .of(variant)
          .copyWith(
            downloadStatus: AsrModelDownloadStatus.downloading,
            downloadProgress: 0,
            clearError: true,
          ),
    );
    final session = ++_nextDownloadSession;
    final cancelToken = CancelToken();
    _cancelTokens[variant] = cancelToken;
    _downloadSessions[variant] = session;
    final task = _runDownload(variant, session, cancelToken);
    _downloadTasks[variant] = task;
    try {
      await task;
    } finally {
      if (identical(_downloadTasks[variant], task)) {
        _downloadTasks.remove(variant);
      }
    }
  }

  bool _isCurrent(
    KokoroModelVariant variant,
    int session,
    CancelToken cancelToken,
  ) =>
      _downloadSessions[variant] == session &&
      identical(_cancelTokens[variant], cancelToken);

  Future<void> _runDownload(
    KokoroModelVariant variant,
    int session,
    CancelToken cancelToken,
  ) async {
    await _persistDownloaded(variant, false);
    final manager = ref.read(kokoroModelManagerProvider(variant));
    try {
      await manager.downloadModel(
        cancelToken: cancelToken,
        onProgress: (p) {
          if (!_isCurrent(variant, session, cancelToken)) return;
          _set(
            variant,
            state.of(variant).copyWith(downloadProgress: p.progress),
          );
        },
      );
      if (!_isCurrent(variant, session, cancelToken)) return;
      final localSize = await manager.modelLocalSize();
      if (!_isCurrent(variant, session, cancelToken)) return;
      _set(
        variant,
        state
            .of(variant)
            .copyWith(
              downloadStatus: AsrModelDownloadStatus.downloaded,
              downloadProgress: 1.0,
              localSizeBytes: localSize,
            ),
      );
      await _persistDownloaded(variant, true);
      if (_isCurrent(variant, session, cancelToken)) {
        _cancelTokens.remove(variant);
        _downloadSessions.remove(variant);
      }
    } catch (e) {
      if (!_isCurrent(variant, session, cancelToken)) return;
      // 取消不是失败：恢复未下载态，不显错误。
      final isCancelled =
          (e is DioException && e.type == DioExceptionType.cancel) ||
          (e is ReliableDownloadException &&
              e.kind == ReliableDownloadFailure.cancelled);
      if (isCancelled) {
        _set(
          variant,
          state
              .of(variant)
              .copyWith(
                downloadStatus: AsrModelDownloadStatus.notDownloaded,
                downloadProgress: 0,
              ),
        );
      } else {
        // 原始异常打日志（诊断用），向用户只展示归类后的友好文案。
        AppLogger.log('KokoroModel', '✗ download failed ($variant): $e');
        _set(
          variant,
          state
              .of(variant)
              .copyWith(
                downloadStatus: AsrModelDownloadStatus.failed,
                downloadError: classifyDownloadFailure(e),
              ),
        );
      }
      _cancelTokens.remove(variant);
      _downloadSessions.remove(variant);
      await _persistDownloaded(variant, false);
    }
  }

  Future<void> _persistDownloaded(KokoroModelVariant v, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_downloadedKey(v), value);
    } catch (e) {
      AppLogger.log('KokoroModel', '写 SP 失败: $e');
    }
  }
}

/// 启动期从持久化 + 文件系统构建两个变体的初始状态。
///
/// [managerOf] 按变体返回对应管理器（main() 注入真实实现，测试注入 fake）。
Future<KokoroModelsState> loadInitialKokoroModelState({
  required SharedPreferences prefs,
  required KokoroModelManager Function(KokoroModelVariant) managerOf,
}) async {
  final map = <KokoroModelVariant, KokoroModelState>{};
  for (final variant in KokoroModelVariant.values) {
    final manager = managerOf(variant);
    final persisted = prefs.getBool(_downloadedKey(variant)) ?? false;
    final localSize = await manager.modelLocalSize();
    // 以文件系统校验为准：标记为真但关键文件缺失则降级。
    final fullyDownloaded = persisted && await manager.isModelDownloaded();
    map[variant] = KokoroModelState(
      downloadStatus: _deriveStatus(
        fullyDownloaded: fullyDownloaded,
        localSizeBytes: localSize,
      ),
      localSizeBytes: localSize,
    );
  }
  return KokoroModelsState(map);
}
