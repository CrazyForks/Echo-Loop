/// 百度网盘导入 UI Controller。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/audio_item.dart';
import '../../../analytics/analytics_providers.dart';
import '../../../analytics/analytics_service.dart';
import '../../../analytics/models/event_names.dart';
import '../../../providers/audio_library_provider.dart';
import '../../../providers/collection_provider.dart';
import '../../audio_import/audio_import_models.dart';
import '../../audio_import/subtitle_pairing.dart';
import '../data/baidu_credential_repository.dart';
import '../data/baidu_netdisk_api.dart';
import '../data/baidu_netdisk_import_service.dart';
import '../models/baidu_oauth_session.dart';
import '../models/baidu_oauth_session_status.dart';
import '../models/cloud_drive_models.dart';
import '../services/baidu_oauth_launcher.dart';
import 'baidu_netdisk_providers.dart';

/// 百度网盘导入流程阶段。
enum BaiduNetdiskImportPhase {
  /// 初始状态。
  idle,

  /// 需要授权。
  authorizationRequired,

  /// 正在打开授权页/轮询授权结果。
  authorizing,

  /// 正在加载目录。
  loading,

  /// 目录可浏览。
  ready,

  /// 正在导入选中文件。
  importing,

  /// 导入完成。
  completed,

  /// 失败。
  failed,
}

/// 百度网盘导入 UI 状态。
@immutable
class BaiduNetdiskImportState {
  /// 构造状态。
  const BaiduNetdiskImportState({
    required this.phase,
    this.currentPath = '/',
    this.entries = const <CloudDriveEntry>[],
    this.selectedFsIds = const <int>{},
    this.importItemStatuses = const <int, AudioImportSelectionStatus>{},
    this.importDuplicateExistingNames = const <int, String>{},
    this.importedItemsByFsId = const <int, AudioItem>{},
    this.errorMessage,
    this.importOutcome,
    this.importingEntry,
    this.importProgress = -1,
    this.importingIndex = 0,
    this.importTotal = 0,
  });

  /// 初始状态。
  const BaiduNetdiskImportState.idle()
    : this(phase: BaiduNetdiskImportPhase.idle);

  /// 当前阶段。
  final BaiduNetdiskImportPhase phase;

  /// 当前目录。
  final String currentPath;

  /// 当前目录条目。
  final List<CloudDriveEntry> entries;

  /// 已选择的可导入文件 fs_id（音频 + 字幕）。
  final Set<int> selectedFsIds;

  /// 本次导入中每个音频 fs_id 对应的行状态。
  final Map<int, AudioImportSelectionStatus> importItemStatuses;

  /// 重复跳过音频 fs_id 对应的库中已有音频名。
  final Map<int, String> importDuplicateExistingNames;

  /// 成功导入音频 fs_id 对应的最终音频项。
  final Map<int, AudioItem> importedItemsByFsId;

  /// 错误消息。
  final String? errorMessage;

  /// 导入结果。
  final CloudDriveImportOutcome? importOutcome;

  /// 当前正在导入的条目。
  final CloudDriveEntry? importingEntry;

  /// 当前文件下载进度；-1 表示不定进度。
  final double importProgress;

  /// 当前正在导入的音频序号，1-based；0 表示未知。
  final int importingIndex;

  /// 本批次音频总数。
  final int importTotal;

  /// 是否忙碌。
  bool get isBusy =>
      phase == BaiduNetdiskImportPhase.authorizing ||
      phase == BaiduNetdiskImportPhase.loading ||
      phase == BaiduNetdiskImportPhase.importing;

  /// 可导入的音频条目。
  List<CloudDriveEntry> get selectedAudioEntries {
    return entries
        .where((entry) => selectedFsIds.contains(entry.fsId))
        .where(_isImportableAudio)
        .toList(growable: false);
  }

  /// 已选择的字幕条目。
  List<CloudDriveEntry> get selectedSubtitleEntries {
    return entries
        .where((entry) => selectedFsIds.contains(entry.fsId))
        .where(_isImportableSubtitle)
        .toList(growable: false);
  }

  /// 当前目录内可选择的导入条目。
  List<CloudDriveEntry> get selectableEntries {
    return entries.where(_isSelectableImportEntry).toList(growable: false);
  }

  /// 当前目录内是否已全选可导入条目。
  bool get isAllSelectableSelected {
    final selectable = selectableEntries;
    return selectable.isNotEmpty &&
        selectable.every((entry) => selectedFsIds.contains(entry.fsId));
  }

  /// 复制状态。
  BaiduNetdiskImportState copyWith({
    BaiduNetdiskImportPhase? phase,
    String? currentPath,
    List<CloudDriveEntry>? entries,
    Set<int>? selectedFsIds,
    Map<int, AudioImportSelectionStatus>? importItemStatuses,
    Map<int, String>? importDuplicateExistingNames,
    Map<int, AudioItem>? importedItemsByFsId,
    Object? errorMessage = _sentinel,
    Object? importOutcome = _sentinel,
    Object? importingEntry = _sentinel,
    double? importProgress,
    int? importingIndex,
    int? importTotal,
  }) {
    return BaiduNetdiskImportState(
      phase: phase ?? this.phase,
      currentPath: currentPath ?? this.currentPath,
      entries: entries ?? this.entries,
      selectedFsIds: selectedFsIds ?? this.selectedFsIds,
      importItemStatuses: importItemStatuses ?? this.importItemStatuses,
      importDuplicateExistingNames:
          importDuplicateExistingNames ?? this.importDuplicateExistingNames,
      importedItemsByFsId: importedItemsByFsId ?? this.importedItemsByFsId,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      importOutcome: identical(importOutcome, _sentinel)
          ? this.importOutcome
          : importOutcome as CloudDriveImportOutcome?,
      importingEntry: identical(importingEntry, _sentinel)
          ? this.importingEntry
          : importingEntry as CloudDriveEntry?,
      importProgress: importProgress ?? this.importProgress,
      importingIndex: importingIndex ?? this.importingIndex,
      importTotal: importTotal ?? this.importTotal,
    );
  }
}

/// 百度网盘导入 Controller provider。
final baiduNetdiskImportControllerProvider =
    StateNotifierProvider.autoDispose<
      BaiduNetdiskImportController,
      BaiduNetdiskImportState
    >((ref) {
      return BaiduNetdiskImportController(
        credentialRepository: ref.watch(baiduCredentialRepositoryProvider),
        api: ref.watch(baiduNetdiskApiProvider),
        importService: ref.watch(baiduNetdiskImportServiceProvider),
        launcher: ref.watch(baiduOAuthLauncherProvider),
        audioLibrary: ref.watch(audioLibraryProvider.notifier),
        readAudioLibraryState: () => ref.read(audioLibraryProvider),
        collectionList: ref.watch(collectionListProvider.notifier),
        readCollectionState: () => ref.read(collectionListProvider),
        analytics: ref.read(analyticsServiceProvider),
      );
    });

/// 百度网盘导入 Controller。
class BaiduNetdiskImportController
    extends StateNotifier<BaiduNetdiskImportState> {
  /// 构造 Controller。
  BaiduNetdiskImportController({
    required BaiduCredentialRepository credentialRepository,
    required BaiduNetdiskApi api,
    required BaiduNetdiskImportService importService,
    required BaiduOAuthLauncher launcher,
    required AudioLibrary audioLibrary,
    required AudioLibraryState Function() readAudioLibraryState,
    required CollectionList collectionList,
    required CollectionState Function() readCollectionState,
    AnalyticsService? analytics,
    TargetPlatform? platform,
  }) : _credentialRepository = credentialRepository,
       _api = api,
       _importService = importService,
       _launcher = launcher,
       _audioLibrary = audioLibrary,
       _readAudioLibraryState = readAudioLibraryState,
       _collectionList = collectionList,
       _readCollectionState = readCollectionState,
       _analytics = analytics,
       _platform = platform,
       super(const BaiduNetdiskImportState.idle());

  final BaiduCredentialRepository _credentialRepository;
  final BaiduNetdiskApi _api;
  final BaiduNetdiskImportService _importService;
  final BaiduOAuthLauncher _launcher;
  final AudioLibrary _audioLibrary;
  final AudioLibraryState Function() _readAudioLibraryState;
  final CollectionList _collectionList;
  final CollectionState Function() _readCollectionState;
  final AnalyticsService? _analytics;
  final TargetPlatform? _platform;

  CancelToken? _cancelToken;
  int _sessionId = 0;

  @override
  void dispose() {
    _cancelToken?.cancel('disposed');
    super.dispose();
  }

  /// 初始化并加载根目录；无凭证时进入授权态。
  Future<void> loadInitial() => loadDirectory('/');

  /// 加载指定目录。
  Future<void> loadDirectory(String path) async {
    if (state.isBusy) return;
    final accessToken = await _credentialRepository.getValidAccessToken();
    if (accessToken == null) {
      state = state.copyWith(
        phase: BaiduNetdiskImportPhase.authorizationRequired,
        currentPath: path,
        errorMessage: null,
      );
      return;
    }
    await _loadDirectoryWithToken(path: path, accessToken: accessToken);
  }

  /// 打开百度授权并轮询完成结果。
  Future<void> authorizeAndLoad() async {
    if (state.isBusy) return;
    _sessionId++;
    final sid = _sessionId;
    state = state.copyWith(
      phase: BaiduNetdiskImportPhase.authorizing,
      errorMessage: null,
    );
    try {
      final session = await _credentialRepository.createSession(_platformName);
      await _launcher.open(session.authorizationUri);
      while (mounted && sid == _sessionId) {
        await Future<void>.delayed(session.pollInterval);
        if (!mounted || sid != _sessionId) return;
        final status = await _credentialRepository.fetchStatus(session);
        switch (status.phase) {
          case BaiduOAuthSessionPhase.pending:
          case BaiduOAuthSessionPhase.exchanging:
            continue;
          case BaiduOAuthSessionPhase.completed:
            final credential = status.credential!;
            await _credentialRepository.persistCompletedSession(
              session: session,
              credential: credential,
            );
            await _loadDirectoryWithToken(
              path: state.currentPath,
              accessToken: credential.accessToken,
            );
            return;
          case BaiduOAuthSessionPhase.canceled:
          case BaiduOAuthSessionPhase.failed:
            state = state.copyWith(
              phase: BaiduNetdiskImportPhase.authorizationRequired,
              errorMessage:
                  status.error?.message ?? 'Baidu authorization failed.',
            );
            return;
        }
      }
    } catch (error) {
      if (sid != _sessionId) return;
      state = state.copyWith(
        phase: BaiduNetdiskImportPhase.failed,
        errorMessage: _messageForError(error),
      );
    }
  }

  /// 切换文件选择。
  void toggleEntry(CloudDriveEntry entry) {
    if (!_isSelectableImportEntry(entry) || state.isBusy) return;
    final next = Set<int>.of(state.selectedFsIds);
    if (!next.add(entry.fsId)) {
      next.remove(entry.fsId);
    }
    state = state.copyWith(selectedFsIds: next);
  }

  /// 切换当前目录内音频和字幕的全选状态。
  void toggleSelectAll() {
    if (state.isBusy) return;
    final selectable = state.selectableEntries;
    if (selectable.isEmpty) return;
    final next = Set<int>.of(state.selectedFsIds);
    if (state.isAllSelectableSelected) {
      for (final entry in selectable) {
        next.remove(entry.fsId);
      }
    } else {
      for (final entry in selectable) {
        next.add(entry.fsId);
      }
    }
    state = state.copyWith(selectedFsIds: next);
  }

  /// 从导入结果页回到当前目录浏览态。
  ///
  /// 完成态会保留本次选择供列表展示状态；用户返回继续选文件时再清空选择和结果。
  void returnToReady() {
    if (state.isBusy) return;
    state = state.copyWith(
      phase: BaiduNetdiskImportPhase.ready,
      selectedFsIds: const <int>{},
      importItemStatuses: const <int, AudioImportSelectionStatus>{},
      importDuplicateExistingNames: const <int, String>{},
      importedItemsByFsId: const <int, AudioItem>{},
      errorMessage: null,
      importOutcome: null,
      importingEntry: null,
      importProgress: -1,
      importingIndex: 0,
      importTotal: 0,
    );
  }

  /// 导入选中文件。
  Future<void> importSelected({String? collectionId}) async {
    if (state.isBusy) return;
    final selected = state.selectedAudioEntries;
    final subtitles = state.selectedSubtitleEntries;
    if (selected.isEmpty) return;

    _sessionId++;
    final sid = _sessionId;
    _cancelToken = CancelToken();
    state = state.copyWith(
      phase: BaiduNetdiskImportPhase.importing,
      errorMessage: null,
      importingEntry: selected.first,
      importProgress: -1,
      importItemStatuses: {
        for (final entry in selected)
          entry.fsId: AudioImportSelectionStatus.pending,
      },
      importDuplicateExistingNames: const <int, String>{},
      importedItemsByFsId: const <int, AudioItem>{},
      importingIndex: selected.isEmpty ? 0 : 1,
      importTotal: selected.length,
    );
    try {
      final outcome = await _importService.importAudios(
        entries: selected,
        subtitleEntries: subtitles,
        audioLibrary: _audioLibrary,
        audioLibraryState: _readAudioLibraryState(),
        collectionList: collectionId == null ? null : _collectionList,
        collectionState: collectionId == null ? null : _readCollectionState(),
        collectionId: collectionId,
        cancelToken: _cancelToken,
        onProgress: (entry, received, total) {
          if (sid != _sessionId) return;
          final index = selected.indexWhere(
            (audio) => audio.fsId == entry.fsId,
          );
          final statuses = Map<int, AudioImportSelectionStatus>.from(
            state.importItemStatuses,
          );
          statuses[entry.fsId] = AudioImportSelectionStatus.importing;
          state = state.copyWith(
            importingEntry: entry,
            importProgress: total == null || total <= 0 ? -1 : received / total,
            importItemStatuses: statuses,
            importingIndex: index < 0 ? state.importingIndex : index + 1,
            importTotal: selected.length,
          );
        },
        onItemResult: (result) {
          if (sid != _sessionId) return;
          final statuses = Map<int, AudioImportSelectionStatus>.from(
            state.importItemStatuses,
          );
          final duplicateNames = Map<int, String>.from(
            state.importDuplicateExistingNames,
          );
          final importedItems = Map<int, AudioItem>.from(
            state.importedItemsByFsId,
          );
          switch (result.status) {
            case CloudDriveImportItemStatus.added:
              statuses[result.entry.fsId] = AudioImportSelectionStatus.added;
              final item = result.item;
              if (item != null) importedItems[result.entry.fsId] = item;
            case CloudDriveImportItemStatus.duplicate:
              statuses[result.entry.fsId] = AudioImportSelectionStatus.skipped;
              final existingName = result.duplicateExistingName;
              if (existingName != null) {
                duplicateNames[result.entry.fsId] = existingName;
              }
            case CloudDriveImportItemStatus.failed:
              statuses[result.entry.fsId] = AudioImportSelectionStatus.skipped;
          }
          state = state.copyWith(
            importItemStatuses: statuses,
            importDuplicateExistingNames: duplicateNames,
            importedItemsByFsId: importedItems,
          );
        },
      );
      if (sid != _sessionId) return;
      state = state.copyWith(
        phase: BaiduNetdiskImportPhase.completed,
        importOutcome: outcome,
        importingEntry: null,
        importProgress: -1,
        importingIndex: 0,
      );
      _analytics?.track(Events.cloudImportResult, {
        EventParams.result: outcome.wasCanceled
            ? 'cancelled'
            : outcome.failures.isEmpty ? 'completed' : 'partial_failure',
        EventParams.source: 'baidu_netdisk',
        EventParams.selectedCount: selected.length,
        EventParams.addedCount: outcome.added.length,
        EventParams.duplicateCount: outcome.duplicates.length,
        EventParams.failedCount: outcome.failures.length,
      });
    } catch (error) {
      if (sid != _sessionId) return;
      state = state.copyWith(
        phase: BaiduNetdiskImportPhase.failed,
        errorMessage: _messageForError(error),
        importingEntry: null,
      );
      _analytics?.track(Events.cloudImportResult, {
        EventParams.result: 'failed',
        EventParams.source: 'baidu_netdisk',
        EventParams.selectedCount: selected.length,
      });
    } finally {
      if (sid == _sessionId) _cancelToken = null;
    }
  }

  /// 取消当前操作。
  void cancel() {
    _sessionId++;
    _cancelToken?.cancel('user-cancelled');
    _cancelToken = null;
    state = state.copyWith(
      phase: BaiduNetdiskImportPhase.ready,
      importingEntry: null,
      importProgress: -1,
      importItemStatuses: const <int, AudioImportSelectionStatus>{},
      importDuplicateExistingNames: const <int, String>{},
      importedItemsByFsId: const <int, AudioItem>{},
      importingIndex: 0,
      importTotal: 0,
    );
  }

  /// 重置。
  void reset() {
    if (state.isBusy) return;
    state = const BaiduNetdiskImportState.idle();
  }

  Future<void> _loadDirectoryWithToken({
    required String path,
    required String accessToken,
  }) async {
    final previous = state;
    state = state.copyWith(
      phase: BaiduNetdiskImportPhase.loading,
      currentPath: path,
      errorMessage: null,
      selectedFsIds: const <int>{},
      importItemStatuses: const <int, AudioImportSelectionStatus>{},
      importDuplicateExistingNames: const <int, String>{},
      importedItemsByFsId: const <int, AudioItem>{},
      importingIndex: 0,
      importTotal: 0,
    );
    try {
      final page = await _api.listDirectory(
        accessToken: accessToken,
        dir: path,
      );
      state = state.copyWith(
        phase: BaiduNetdiskImportPhase.ready,
        entries: _visibleEntries(page.entries),
      );
    } on BaiduNetdiskFileException catch (error) {
      if (error.kind == BaiduNetdiskFileErrorKind.unauthorized) {
        await _credentialRepository.clearCredential();
        state = previous.copyWith(
          phase: BaiduNetdiskImportPhase.authorizationRequired,
          errorMessage: 'Baidu authorization expired.',
        );
        return;
      }
      state = previous.copyWith(
        phase: BaiduNetdiskImportPhase.failed,
        errorMessage: error.message,
      );
    } catch (error) {
      state = previous.copyWith(
        phase: BaiduNetdiskImportPhase.failed,
        errorMessage: _messageForError(error),
      );
    }
  }

  List<CloudDriveEntry> _visibleEntries(List<CloudDriveEntry> entries) {
    return entries.toList(growable: false);
  }

  BaiduNetdiskPlatform get _platformName {
    final platform = _platform ?? defaultTargetPlatform;
    return switch (platform) {
      TargetPlatform.iOS => BaiduNetdiskPlatform.ios,
      TargetPlatform.android => BaiduNetdiskPlatform.android,
      TargetPlatform.macOS => BaiduNetdiskPlatform.macos,
      TargetPlatform.windows => BaiduNetdiskPlatform.windows,
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => BaiduNetdiskPlatform.linux,
    };
  }

  String _messageForError(Object error) {
    if (error is BaiduReauthorizationRequiredException) {
      return 'Please connect Baidu Netdisk again.';
    }
    if (error is AudioImportException) return error.message;
    if (error is BaiduNetdiskFileException) return error.message;
    return 'Baidu Netdisk import failed.';
  }
}

bool _isImportableAudio(CloudDriveEntry entry) {
  return !entry.isDirectory && audioImportExtensions.contains(entry.extension);
}

bool _isImportableSubtitle(CloudDriveEntry entry) {
  return !entry.isDirectory &&
      subtitleImportExtensions.contains(entry.extension);
}

bool _isSelectableImportEntry(CloudDriveEntry entry) {
  return _isImportableAudio(entry) || _isImportableSubtitle(entry);
}

const _sentinel = Object();
