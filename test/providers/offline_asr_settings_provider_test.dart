import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echo_loop/providers/offline_asr_settings_provider.dart';
import 'package:echo_loop/providers/asr_engine_provider.dart';
import 'package:echo_loop/services/asr/asr_model_manager.dart';
import 'package:echo_loop/services/asr/offline_asr_engine.dart';
import 'package:echo_loop/services/download/download_failure.dart';
import 'package:echo_loop/services/reliable_http_downloader.dart';

class _FakeAsrModelManager extends AsrModelManager {
  _FakeAsrModelManager({
    required this.downloaded,
    required this.localSizeBytes,
  });

  final bool downloaded;
  final int localSizeBytes;
  int deleteModelCallCount = 0;

  @override
  Future<bool> isModelDownloaded(String modelId) async => downloaded;

  @override
  Future<int> modelLocalSize(String modelId) async => localSizeBytes;

  @override
  Future<void> deleteModel(String modelId) async {
    deleteModelCallCount += 1;
  }

  @override
  Future<void> cleanupUnknownModels() async {}
}

class _TestOfflineAsrSettingsNotifier extends OfflineAsrSettingsNotifier {
  _TestOfflineAsrSettingsNotifier(this._initialState);

  final OfflineAsrSettingsState _initialState;

  @override
  OfflineAsrSettingsState build() => _initialState;
}

class _DelayedAsrModelManager extends _FakeAsrModelManager {
  _DelayedAsrModelManager() : super(downloaded: false, localSizeBytes: 99);

  final downloadCompleter = Completer<String>();
  CancelToken? downloadCancelToken;

  @override
  Future<String> downloadModel(
    String modelId, {
    void Function(AsrModelDownloadProgress)? onProgress,
    CancelToken? cancelToken,
  }) {
    downloadCancelToken = cancelToken;
    return downloadCompleter.future;
  }
}

void main() {
  const recommendedModel = AsrModelInfo(
    id: 'whisper-base-en-int8',
    displayName: 'Whisper Base.en',
    type: AsrModelType.whisper,
  );

  test('启动加载时保留残留模型大小并标记为 failed', () async {
    SharedPreferences.setMockInitialValues({'offline_asr_enabled': true});
    final prefs = await SharedPreferences.getInstance();
    final manager = _FakeAsrModelManager(
      downloaded: false,
      localSizeBytes: 150 * 1024 * 1024,
    );

    final state = await loadInitialOfflineAsrSettingsState(
      prefs: prefs,
      modelManager: manager,
      recommendedModel: recommendedModel,
      defaultBackend: AsrBackend.offline,
    );

    expect(state.enabled, isTrue);
    expect(state.downloadStatus, AsrModelDownloadStatus.failed);
    expect(state.localSizeBytes, 150 * 1024 * 1024);
  });

  test('启动加载时完整模型保持 downloaded', () async {
    SharedPreferences.setMockInitialValues({
      'offline_asr_enabled': true,
      'offline_asr_downloaded_whisper-base-en-int8': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final manager = _FakeAsrModelManager(
      downloaded: true,
      localSizeBytes: 209 * 1024 * 1024,
    );

    final state = await loadInitialOfflineAsrSettingsState(
      prefs: prefs,
      modelManager: manager,
      recommendedModel: recommendedModel,
      defaultBackend: AsrBackend.offline,
    );

    expect(state.downloadStatus, AsrModelDownloadStatus.downloaded);
    expect(state.localSizeBytes, 209 * 1024 * 1024);
  });

  test('首帧后恢复会用文件校验结果替换默认状态', () async {
    SharedPreferences.setMockInitialValues({
      'offline_asr_downloaded_whisper-base-en-int8': true,
    });
    final manager = _FakeAsrModelManager(
      downloaded: true,
      localSizeBytes: 209 * 1024 * 1024,
    );
    final container = ProviderContainer(
      overrides: [
        asrModelManagerProvider.overrideWithValue(manager),
        recommendedAsrModelProvider.overrideWithValue(recommendedModel),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(offlineAsrSettingsProvider).downloadStatus,
      AsrModelDownloadStatus.notDownloaded,
    );
    await container
        .read(offlineAsrSettingsProvider.notifier)
        .restoreInitialStateFromDisk();

    expect(
      container.read(offlineAsrSettingsProvider).downloadStatus,
      AsrModelDownloadStatus.downloaded,
    );
  });

  test('启动加载时没有完成标记的残留模型按 failed 处理', () async {
    SharedPreferences.setMockInitialValues({
      'offline_asr_enabled': true,
      'offline_asr_downloaded_whisper-base-en-int8': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final manager = _FakeAsrModelManager(
      downloaded: true,
      localSizeBytes: 209 * 1024 * 1024,
    );

    final state = await loadInitialOfflineAsrSettingsState(
      prefs: prefs,
      modelManager: manager,
      recommendedModel: recommendedModel,
      defaultBackend: AsrBackend.offline,
    );

    expect(state.downloadStatus, AsrModelDownloadStatus.failed);
    expect(
      prefs.getBool('offline_asr_downloaded_whisper-base-en-int8'),
      isFalse,
    );
  });

  test('主动取消下载会清理残留并回到未下载态，不显示失败', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final manager = _FakeAsrModelManager(downloaded: false, localSizeBytes: 99);
    final modelId = recommendedModel.id;
    final initialState = OfflineAsrSettingsState(
      backend: AsrBackend.offline,
      recommendedModel: recommendedModel,
      modelStates: {
        modelId: const AsrModelState(
          downloadStatus: AsrModelDownloadStatus.downloading,
          downloadProgress: 0.4,
          localSizeBytes: 99,
          downloadError: DownloadFailureKind.network,
        ),
      },
    );
    final container = ProviderContainer(
      overrides: [
        asrModelManagerProvider.overrideWithValue(manager),
        offlineAsrSettingsProvider.overrideWith(
          () => _TestOfflineAsrSettingsNotifier(initialState),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(offlineAsrSettingsProvider.notifier).cancelDownload();

    final state = container.read(offlineAsrSettingsProvider);
    expect(manager.deleteModelCallCount, 1);
    expect(state.downloadStatus, AsrModelDownloadStatus.notDownloaded);
    expect(state.downloadProgress, 0);
    expect(state.localSizeBytes, 0);
    expect(state.downloadError, isNull);
    expect(prefs.getBool('offline_asr_downloaded_$modelId'), isFalse);
  });

  test('取消后立即重置 UI，底层写入报存储异常仍不显示重试', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final manager = _DelayedAsrModelManager();
    final initialState = OfflineAsrSettingsState(
      backend: AsrBackend.offline,
      recommendedModel: recommendedModel,
    );
    final container = ProviderContainer(
      overrides: [
        asrModelManagerProvider.overrideWithValue(manager),
        offlineAsrSettingsProvider.overrideWith(
          () => _TestOfflineAsrSettingsNotifier(initialState),
        ),
      ],
    );
    addTearDown(container.dispose);

    final download = container
        .read(offlineAsrSettingsProvider.notifier)
        .retryDownload();
    await Future<void>.delayed(Duration.zero);
    expect(manager.downloadCancelToken, isNotNull);

    final cancel = container
        .read(offlineAsrSettingsProvider.notifier)
        .cancelDownload();
    await Future<void>.delayed(Duration.zero);

    final immediateState = container.read(offlineAsrSettingsProvider);
    expect(immediateState.downloadStatus, AsrModelDownloadStatus.notDownloaded);
    expect(immediateState.downloadProgress, 0);
    expect(immediateState.localSizeBytes, 0);
    expect(immediateState.downloadError, isNull);

    manager.downloadCompleter.completeError(
      const ReliableDownloadException(
        'directory removed during cancellation',
        kind: ReliableDownloadFailure.storage,
      ),
    );
    await cancel;
    await download;

    final state = container.read(offlineAsrSettingsProvider);
    expect(state.downloadStatus, AsrModelDownloadStatus.notDownloaded);
    expect(state.downloadError, isNull);
    expect(state.localSizeBytes, 0);
  });
}
