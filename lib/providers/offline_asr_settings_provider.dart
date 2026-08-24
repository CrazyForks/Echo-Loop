/// 离线 ASR 功能设置 Provider。
///
/// 管理本地语音识别的开关状态、模型下载、引擎初始化。
/// 独立于 [AppSettings]，遵循"Provider 按功能域拆分"原则。
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics_providers.dart';
import '../analytics/models/event_names.dart';
import '../services/app_logger.dart';
import '../services/asr/asr_model_manager.dart';
import '../services/asr/offline_asr_engine.dart';
import '../services/download/download_failure.dart';
import '../services/reliable_http_downloader.dart';
import '../utils/app_data_dir.dart';
import 'asr_engine_provider.dart';

/// 进程内是否已检查过 ASR 崩溃面包屑（只检查一次）。
bool _asrCrashMarkerChecked = false;
const _backendKey = 'offline_asr_backend';
const _selectedModelKey = 'offline_asr_selected_model_id';
String _downloadCompletedKey(String modelId) =>
    'offline_asr_downloaded_$modelId';

AsrModelDownloadStatus _deriveStoredDownloadStatus({
  required bool fullyDownloaded,
  required int localSizeBytes,
}) {
  if (fullyDownloaded) {
    return AsrModelDownloadStatus.downloaded;
  }
  if (localSizeBytes > 0) {
    return AsrModelDownloadStatus.failed;
  }
  return AsrModelDownloadStatus.notDownloaded;
}
// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// 语音识别后端类型。
enum AsrBackend {
  /// 平台原生 ASR（iOS/macOS 的 SFSpeechRecognizer）。
  platform,

  /// 离线自建模型 ASR（sherpa-onnx）。
  offline,
}

/// 单个 ASR 模型的下载与校验状态。
class AsrModelState {
  final AsrModelDownloadStatus downloadStatus;
  final double downloadProgress;
  final int localSizeBytes;

  /// 失败时的归类原因（供 UI 显本地化文案）；非失败态为 null。
  final DownloadFailureKind? downloadError;

  const AsrModelState({
    this.downloadStatus = AsrModelDownloadStatus.notDownloaded,
    this.downloadProgress = 0,
    this.localSizeBytes = 0,
    this.downloadError,
  });

  bool get isReady => downloadStatus == AsrModelDownloadStatus.downloaded;

  bool get isDownloading =>
      downloadStatus == AsrModelDownloadStatus.downloading;

  AsrModelState copyWith({
    AsrModelDownloadStatus? downloadStatus,
    double? downloadProgress,
    int? localSizeBytes,
    DownloadFailureKind? downloadError,
    bool clearError = false,
  }) {
    return AsrModelState(
      downloadStatus: downloadStatus ?? this.downloadStatus,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      localSizeBytes: localSizeBytes ?? this.localSizeBytes,
      downloadError: clearError ? null : (downloadError ?? this.downloadError),
    );
  }
}

/// 离线 ASR 功能的完整 UI 状态。
class OfflineAsrSettingsState {
  /// 兼容旧调用的功能开关。语音识别现在是基础能力，业务态恒为 true。
  final bool enabled;

  /// 当前选择的 ASR 后端。
  ///
  /// iOS/macOS 默认 [AsrBackend.platform]，可切换到 [AsrBackend.offline]。
  /// Android 固定 [AsrBackend.offline]。
  final AsrBackend backend;

  /// 引擎是否已就绪（模型已加载到内存）。
  final bool engineReady;

  /// 推荐的模型信息。
  final AsrModelInfo recommendedModel;

  /// 当前选中的 Whisper 模型。
  final AsrModelInfo selectedModel;

  /// 各 Whisper 模型的下载状态（key 为 model id）。
  final Map<String, AsrModelState> modelStates;

  OfflineAsrSettingsState({
    this.enabled = true,
    this.backend = AsrBackend.platform,
    this.engineReady = false,
    required this.recommendedModel,
    AsrModelInfo? selectedModel,
    Map<String, AsrModelState> modelStates = const {},
    AsrModelDownloadStatus? downloadStatus,
    double? downloadProgress,
    int? localSizeBytes,
    DownloadFailureKind? downloadError,
  }) : selectedModel = selectedModel ?? recommendedModel,
       modelStates = _withLegacySelectedModelState(
         modelStates,
         selectedModel ?? recommendedModel,
         downloadStatus,
         downloadProgress,
         localSizeBytes,
         downloadError,
       );

  static Map<String, AsrModelState> _withLegacySelectedModelState(
    Map<String, AsrModelState> states,
    AsrModelInfo selectedModel,
    AsrModelDownloadStatus? downloadStatus,
    double? downloadProgress,
    int? localSizeBytes,
    DownloadFailureKind? downloadError,
  ) {
    if (downloadStatus == null &&
        downloadProgress == null &&
        localSizeBytes == null &&
        downloadError == null) {
      return states;
    }
    final current = states[selectedModel.id] ?? const AsrModelState();
    return {
      ...states,
      selectedModel.id: current.copyWith(
        downloadStatus: downloadStatus,
        downloadProgress: downloadProgress,
        localSizeBytes: localSizeBytes,
        downloadError: downloadError,
      ),
    };
  }

  AsrModelState modelStateOf(String modelId) =>
      modelStates[modelId] ?? const AsrModelState();

  AsrModelState get selectedModelState => modelStateOf(selectedModel.id);

  /// 模型下载状态（当前选中模型）。
  AsrModelDownloadStatus get downloadStatus =>
      selectedModelState.downloadStatus;

  /// 下载进度 0.0~1.0（当前选中模型）。
  double get downloadProgress => selectedModelState.downloadProgress;

  /// 当前选中模型本地占用空间（字节）。
  int get localSizeBytes => selectedModelState.localSizeBytes;

  /// 当前选中模型下载错误。
  DownloadFailureKind? get downloadError => selectedModelState.downloadError;

  int get totalDownloadedModelBytes => modelStates.values.fold<int>(
    0,
    (sum, s) => s.isReady ? sum + s.localSizeBytes : sum,
  );

  /// 是否正在下载。
  bool get isDownloading => selectedModelState.isDownloading;

  /// 离线 ASR 是否完全就绪（模型已下载 + 引擎已加载）。
  bool get isOfflineReady =>
      enabled &&
      backend == AsrBackend.offline &&
      downloadStatus == AsrModelDownloadStatus.downloaded &&
      engineReady;

  OfflineAsrSettingsState copyWith({
    bool? enabled,
    AsrBackend? backend,
    AsrModelDownloadStatus? downloadStatus,
    double? downloadProgress,
    int? localSizeBytes,
    DownloadFailureKind? downloadError,
    bool clearError = false,
    bool? engineReady,
    AsrModelInfo? selectedModel,
    Map<String, AsrModelState>? modelStates,
  }) {
    final nextSelected = selectedModel ?? this.selectedModel;
    final currentStates = modelStates ?? this.modelStates;
    final nextStates = _withLegacySelectedModelState(
      currentStates,
      nextSelected,
      downloadStatus,
      downloadProgress,
      localSizeBytes,
      clearError ? null : downloadError,
    );
    return OfflineAsrSettingsState(
      enabled: true,
      backend: backend ?? this.backend,
      engineReady: engineReady ?? this.engineReady,
      recommendedModel: recommendedModel,
      selectedModel: nextSelected,
      modelStates: clearError
          ? {
              ...nextStates,
              nextSelected.id:
                  (nextStates[nextSelected.id] ?? const AsrModelState())
                      .copyWith(clearError: true),
            }
          : nextStates,
    );
  }

  OfflineAsrSettingsState withModelState(String modelId, AsrModelState s) {
    return copyWith(modelStates: {...modelStates, modelId: s});
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// 离线 ASR 功能设置 Provider（keepAlive，全局单例）。
final offlineAsrSettingsProvider =
    NotifierProvider<OfflineAsrSettingsNotifier, OfflineAsrSettingsState>(
      OfflineAsrSettingsNotifier.new,
    );

/// 应用启动时预加载的离线 ASR 初始状态。
///
/// 通过 main() 注入，避免首次点击语音练习时先读到默认值。
/// 启动时只读取“下载完成”持久化标记，不再做文件系统重校验。
final initialOfflineAsrSettingsStateProvider =
    Provider<OfflineAsrSettingsState>((ref) {
      final recommended = ref.read(recommendedAsrModelProvider);
      return OfflineAsrSettingsState(recommendedModel: recommended);
    });

/// 设置页是否显示 AI 语音识别入口。
///
/// 全平台显示（Web 除外）。
final showOfflineAsrSectionProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  return true;
});

/// 推荐的 ASR 模型。
///
/// 首帧前不再读取设备内存；这里先提供稳定的保守默认值，首帧后的状态恢复
/// 会继续按既有规则读取并更新已保存的用户选择。
final recommendedAsrModelProvider = Provider<AsrModelInfo>(
  (ref) => availableModels.first,
);

/// 离线 ASR 设置 Notifier。
class OfflineAsrSettingsNotifier extends Notifier<OfflineAsrSettingsState> {
  final Map<String, CancelToken> _downloadCancelTokens = {};
  final Map<String, Future<void>> _downloadTasks = {};
  final Set<String> _cancellingModelIds = {};

  @override
  OfflineAsrSettingsState build() {
    ref.onDispose(() {
      for (final token in _downloadCancelTokens.values) {
        token.cancel();
      }
    });

    return ref.read(initialOfflineAsrSettingsStateProvider);
  }

  /// 首帧后按既有规则扫描本地模型目录，并用结果刷新当前状态。
  Future<void> restoreInitialStateFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final modelManager = ref.read(asrModelManagerProvider);
    final defaultBackend = Platform.isAndroid
        ? AsrBackend.offline
        : AsrBackend.platform;
    state = await loadInitialOfflineAsrSettingsState(
      prefs: prefs,
      modelManager: modelManager,
      recommendedModel: ref.read(recommendedAsrModelProvider),
      defaultBackend: defaultBackend,
    );
    // 沿用原启动期行为：后台清理历史废弃模型目录，不阻塞状态恢复。
    unawaited(modelManager.cleanupUnknownModels());
  }

  /// 兼容旧调用：语音识别基础能力常开；offline 后端下确保当前模型就绪。
  Future<void> enable() async {
    if (state.backend == AsrBackend.platform) {
      state = state.copyWith(enabled: true, clearError: true);
      ref.read(analyticsServiceProvider).track(Events.asrSettingChanged, {
        EventParams.asrEnabled: true,
        EventParams.asrBackend: AsrBackend.platform.name,
      });
      return;
    }

    if (state.isDownloading) return;

    final modelId = state.selectedModel.id;
    final modelManager = ref.read(asrModelManagerProvider);

    if (state.downloadStatus == AsrModelDownloadStatus.downloaded) {
      final localSize = await modelManager.modelLocalSize(modelId);
      state = state
          .withModelState(
            modelId,
            state
                .modelStateOf(modelId)
                .copyWith(
                  downloadStatus: AsrModelDownloadStatus.downloaded,
                  localSizeBytes: localSize,
                  clearError: true,
                ),
          )
          .copyWith(enabled: true);
      await _persistDownloadCompleted(modelId, true);
      await _initializeEngine(modelId);
      ref.read(analyticsServiceProvider).track(Events.asrSettingChanged, {
        EventParams.asrEnabled: true,
        EventParams.asrBackend: AsrBackend.offline.name,
      });
    } else {
      state = state.copyWith(enabled: true, clearError: true);
      ref.read(analyticsServiceProvider).track(Events.asrSettingChanged, {
        EventParams.asrEnabled: true,
        EventParams.asrBackend: AsrBackend.offline.name,
      });
      await _downloadAndInitialize(modelId);
    }
  }

  /// 兼容旧调用：不再关闭语音识别基础能力，仅取消下载并卸载离线引擎。
  Future<void> disable() async {
    for (final token in _downloadCancelTokens.values) {
      token.cancel();
    }
    _downloadCancelTokens.clear();
    await unloadEngine();
    state = state.copyWith(enabled: true, engineReady: false, clearError: true);
  }

  /// 按需加载引擎（进入录音页面时调用）。
  Future<void> loadEngine() async {
    if (state.engineReady) return;
    if (state.backend != AsrBackend.offline) return;
    if (state.downloadStatus != AsrModelDownloadStatus.downloaded) return;
    await _initializeEngine(state.selectedModel.id);
  }

  /// 卸载引擎释放内存（退出录音页面时调用）。
  Future<void> unloadEngine() async {
    if (!state.engineReady) return;
    final engine = ref.read(offlineAsrEngineProvider);
    await engine.dispose();
    state = state.copyWith(engineReady: false);
  }

  /// 兼容旧调用：当前模型不再通过关闭流程删除。
  Future<void> disableAndDelete() async {
    await disable();
  }

  /// 选择一个 Whisper 模型。离线后端下未下载则立即下载，已下载则初始化。
  Future<void> selectModel(AsrModelInfo model) async {
    if (state.selectedModel.id == model.id) {
      if (state.backend == AsrBackend.offline && !state.isDownloading) {
        if (state.downloadStatus == AsrModelDownloadStatus.downloaded) {
          await _initializeEngine(model.id);
        } else {
          await _downloadAndInitialize(model.id);
        }
      }
      return;
    }

    await unloadEngine();
    state = state.copyWith(selectedModel: model, engineReady: false);
    await _persistSelectedModel(model.id);

    if (state.backend == AsrBackend.offline) {
      if (state.downloadStatus == AsrModelDownloadStatus.downloaded) {
        await _initializeEngine(model.id);
      } else if (!state.isDownloading) {
        await _downloadAndInitialize(model.id);
      }
    }
  }

  /// 删除本地模型。Echo Loop AI 当前使用的模型不可删除；Apple Speech 下可删任意模型。
  Future<void> deleteModel([String? modelId]) async {
    final targetId = modelId ?? state.selectedModel.id;
    if (state.backend == AsrBackend.offline &&
        targetId == state.selectedModel.id) {
      return;
    }
    _downloadCancelTokens.remove(targetId)?.cancel();
    final modelManager = ref.read(asrModelManagerProvider);
    await modelManager.deleteModel(targetId);
    state = state.withModelState(targetId, const AsrModelState());
    await _persistDownloadCompleted(targetId, false);
  }

  /// 删除所有已下载且当前未使用的 Whisper 模型。
  Future<void> deleteDownloadedModels({required bool includeSelected}) async {
    final downloaded = availableModels.where((m) {
      if (!includeSelected && m.id == state.selectedModel.id) return false;
      return state.modelStateOf(m.id).isReady;
    }).toList();
    for (final model in downloaded) {
      await deleteModel(model.id);
    }
  }

  /// 重试下载当前或指定模型。
  Future<void> retryDownload([String? modelId]) async {
    final targetId = modelId ?? state.selectedModel.id;
    state = state.withModelState(
      targetId,
      state.modelStateOf(targetId).copyWith(clearError: true),
    );
    await _downloadAndInitialize(targetId);
  }

  /// 取消当前或指定模型正在进行的下载。
  Future<void> cancelDownload([String? modelId]) async {
    final targetId = modelId ?? state.selectedModel.id;
    final task = _downloadTasks[targetId];
    _downloadCancelTokens.remove(targetId)?.cancel();
    // 与 TTS 下载统一：用户点击取消后立即撤销下载 UI，文件句柄释放和目录清理
    // 在后台继续，避免大文件下载的取消反馈被底层 I/O 阻塞。
    state = state.withModelState(
      targetId,
      const AsrModelState(downloadStatus: AsrModelDownloadStatus.notDownloaded),
    );
    await _persistDownloadCompleted(targetId, false);
    if (task == null) {
      // 兼容状态恢复后的残留：没有在途下载也要回收目录。
      await ref.read(asrModelManagerProvider).deleteModel(targetId);
      return;
    }
    _cancellingModelIds.add(targetId);
    // 等待下载器释放文件句柄后再删除目录，避免主动取消被记录成 PathNotFound/storage 失败。
    try {
      await task;
      final modelManager = ref.read(asrModelManagerProvider);
      // 主动取消不是失败；删除整个模型目录，连同下载器留下的 `.part` 和元数据一起清理。
      await modelManager.deleteModel(targetId);
    } finally {
      _cancellingModelIds.remove(targetId);
    }
  }

  // ---------------------------------------------------------------------------
  // 内部方法
  // ---------------------------------------------------------------------------

  Future<void> _downloadAndInitialize(String modelId) async {
    if (_cancellingModelIds.contains(modelId)) return;
    final task = _runDownloadAndInitialize(modelId);
    _downloadTasks[modelId] = task;
    try {
      await task;
    } finally {
      if (identical(_downloadTasks[modelId], task)) {
        _downloadTasks.remove(modelId);
      }
    }
  }

  Future<void> _runDownloadAndInitialize(String modelId) async {
    await _persistDownloadCompleted(modelId, false);
    state = state.withModelState(
      modelId,
      state
          .modelStateOf(modelId)
          .copyWith(
            downloadStatus: AsrModelDownloadStatus.downloading,
            downloadProgress: 0,
            clearError: true,
          ),
    );

    final cancelToken = CancelToken();
    _downloadCancelTokens[modelId] = cancelToken;
    final modelManager = ref.read(asrModelManagerProvider);

    try {
      await modelManager.downloadModel(
        modelId,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (cancelToken.isCancelled ||
              !identical(_downloadCancelTokens[modelId], cancelToken)) {
            return;
          }
          state = state.withModelState(
            modelId,
            state
                .modelStateOf(modelId)
                .copyWith(downloadProgress: progress.progress),
          );
        },
      );

      // 下载 VAD 模型（静默，不影响主进度条）。
      if (!await modelManager.isModelDownloaded(vadModelId)) {
        await modelManager.downloadModel(vadModelId, cancelToken: cancelToken);
      }

      if (cancelToken.isCancelled ||
          !identical(_downloadCancelTokens[modelId], cancelToken)) {
        return;
      }
      _downloadCancelTokens.remove(modelId);
      final localSize = await modelManager.modelLocalSize(modelId);

      state = state.withModelState(
        modelId,
        state
            .modelStateOf(modelId)
            .copyWith(
              downloadStatus: AsrModelDownloadStatus.downloaded,
              downloadProgress: 1.0,
              localSizeBytes: localSize,
            ),
      );
      await _persistDownloadCompleted(modelId, true);

      await _initializeEngine(modelId);
    } catch (e) {
      final isCurrentDownload = identical(
        _downloadCancelTokens[modelId],
        cancelToken,
      );
      if (isCurrentDownload) {
        _downloadCancelTokens.remove(modelId);
      } else if (_downloadCancelTokens.containsKey(modelId)) {
        // 同一模型已发起新下载，旧会话不得覆盖其状态或完成标记。
        return;
      }
      // 取消不是失败：恢复未下载态，不显错误。
      final isCancelled =
          cancelToken.isCancelled ||
          (e is DioException && e.type == DioExceptionType.cancel) ||
          (e is ReliableDownloadException &&
              e.kind == ReliableDownloadFailure.cancelled);
      if (isCancelled) {
        // 文件已由 cancelDownload 的用户动作路径立即清理；这里不能再次删除，
        // 否则迟到回调可能误删用户重试后新任务写入的文件。
        state = state.withModelState(
          modelId,
          state
              .modelStateOf(modelId)
              .copyWith(
                downloadStatus: AsrModelDownloadStatus.notDownloaded,
                downloadProgress: 0,
                localSizeBytes: 0,
                clearError: true,
              ),
        );
      } else {
        // 原始异常打日志（诊断用），向用户只展示归类后的友好文案。
        AppLogger.log('OfflineAsr', '✗ download failed ($modelId): $e');
        state = state.withModelState(
          modelId,
          state
              .modelStateOf(modelId)
              .copyWith(
                downloadStatus: AsrModelDownloadStatus.failed,
                downloadError: classifyDownloadFailure(e),
              ),
        );
      }
      await _persistDownloadCompleted(modelId, false);
    }
  }

  /// 检查上次是否疑似崩溃在 ASR 推理（残留面包屑），有则记录+上报后清除。
  ///
  /// 进程内只检查一次。放在引擎初始化前——即真正再次跑 native 推理之前。
  Future<void> _reportPreviousAsrCrashIfAny() async {
    if (_asrCrashMarkerChecked) return;
    _asrCrashMarkerChecked = true;
    try {
      final f = File(await asrCrashMarkerPath());
      if (!await f.exists()) return;
      final info = (await f.readAsString()).trim();
      await f.delete();
      AppLogger.log('ASRCrash', '⚠ 检测到上次疑似崩溃在 ASR 推理: $info');
      ref.read(analyticsServiceProvider).track(
        Events.asrInferenceCrashSuspected,
        {'detail': info},
      );
    } catch (_) {
      // 忽略：面包屑检查不应影响引擎初始化。
    }
  }

  Future<void> _initializeEngine(String modelId) async {
    if (modelId != state.selectedModel.id) return;
    await _reportPreviousAsrCrashIfAny();
    final engine = ref.read(offlineAsrEngineProvider);
    final modelManager = ref.read(asrModelManagerProvider);
    final modelDir = await modelManager.modelDir(modelId);
    final modelInfo = _modelInfoById(modelId);

    // VAD 模型路径（可选，未下载时跳过静音裁剪）。
    String? vadPath;
    if (await modelManager.isModelDownloaded(vadModelId)) {
      final vadDir = await modelManager.modelDir(vadModelId);
      vadPath = '$vadDir/silero_vad.onnx';
    }

    try {
      await engine.initialize(
        AsrModelConfig(
          model: modelInfo,
          modelDir: modelDir,
          numThreads: AsrModelConfig.recommendedThreads(),
          vadModelPath: vadPath,
        ),
      );
      state = state.copyWith(engineReady: true);
    } catch (e) {
      // 引擎初始化失败不是下载失败，无确定归类 → 通用文案；原始异常打日志。
      AppLogger.log('OfflineAsr', '✗ engine init failed ($modelId): $e');
      state = state
          .withModelState(
            modelId,
            state
                .modelStateOf(modelId)
                .copyWith(
                  downloadStatus: AsrModelDownloadStatus.failed,
                  downloadError: DownloadFailureKind.unknown,
                ),
          )
          .copyWith(engineReady: false);
      await _persistDownloadCompleted(modelId, false);
    }
  }

  Future<void> _persistBackend(AsrBackend value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, value.name);
  }

  Future<void> _persistSelectedModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, modelId);
  }

  AsrModelInfo _modelInfoById(String modelId) {
    return availableModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => state.recommendedModel,
    );
  }

  /// 切换 ASR 后端。
  ///
  /// 切到 offline 且模型未下载时自动触发下载。
  /// 切到 platform 时不影响已下载的模型文件。
  Future<void> setBackend(AsrBackend backend) async {
    if (state.backend == backend) return;

    if (backend == AsrBackend.platform) {
      await unloadEngine();
    }

    // 切离 offline 时取消正在进行的下载
    if (state.backend == AsrBackend.offline && state.isDownloading) {
      final modelId = state.selectedModel.id;
      _downloadCancelTokens.remove(modelId)?.cancel();
      state = state
          .withModelState(
            modelId,
            state
                .modelStateOf(modelId)
                .copyWith(
                  downloadStatus: AsrModelDownloadStatus.notDownloaded,
                  downloadProgress: 0,
                  clearError: true,
                ),
          )
          .copyWith(backend: backend);
    } else {
      state = state.copyWith(backend: backend);
    }
    await _persistBackend(backend);
    ref.read(analyticsServiceProvider).track(Events.asrSettingChanged, {
      EventParams.asrEnabled: state.enabled,
      EventParams.asrBackend: backend.name,
    });

    final modelId = state.selectedModel.id;

    // 切到 offline → 确保当前模型就绪。
    if (backend == AsrBackend.offline) {
      if (state.downloadStatus == AsrModelDownloadStatus.downloaded) {
        await _initializeEngine(modelId);
      } else if (state.downloadStatus != AsrModelDownloadStatus.downloading) {
        await _downloadAndInitialize(modelId);
      }
    }
  }

  /// 持久化”模型已完整下载”标记。
  ///
  /// 该标记只作为启动恢复和状态核对的快速索引，最终仍以文件系统校验为准。
  Future<void> _persistDownloadCompleted(String modelId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_downloadCompletedKey(modelId), value);
  }
}

/// 启动期从持久化和模型文件系统中构建离线 ASR 初始状态。
Future<OfflineAsrSettingsState> loadInitialOfflineAsrSettingsState({
  required SharedPreferences prefs,
  required AsrModelManager modelManager,
  required AsrModelInfo recommendedModel,
  required AsrBackend defaultBackend,
}) async {
  final backendName = prefs.getString(_backendKey);
  final backend = backendName == AsrBackend.offline.name
      ? AsrBackend.offline
      : backendName == AsrBackend.platform.name
      ? AsrBackend.platform
      : defaultBackend;
  final selectedModelId = prefs.getString(_selectedModelKey);
  final selectedModel = availableModels.firstWhere(
    (m) => m.id == selectedModelId,
    orElse: () => recommendedModel,
  );

  final modelStates = <String, AsrModelState>{};
  for (final model in availableModels) {
    final persistedDownloaded =
        prefs.getBool(_downloadCompletedKey(model.id)) ?? false;
    final localSize = await modelManager.modelLocalSize(model.id);
    final fullyDownloaded =
        persistedDownloaded && await modelManager.isModelDownloaded(model.id);
    modelStates[model.id] = AsrModelState(
      downloadStatus: _deriveStoredDownloadStatus(
        fullyDownloaded: fullyDownloaded,
        localSizeBytes: localSize,
      ),
      localSizeBytes: localSize,
    );
  }

  return OfflineAsrSettingsState(
    enabled: true,
    backend: backend,
    recommendedModel: recommendedModel,
    selectedModel: selectedModel,
    modelStates: modelStates,
  );
}
