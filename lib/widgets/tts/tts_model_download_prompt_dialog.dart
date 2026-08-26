/// TTS 发音前的本地模型就绪门控。
///
/// 模型下载仍由设置和控制器在后台自动触发；本文件只复用全局下载状态展示进度、
/// 失败与重试。用户点击发音时模型未就绪，本次发音不会在下载完成后自动继续。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/tts/kokoro_model_provider.dart';
import '../../providers/tts/piper_model_provider.dart';
import '../../providers/tts/tts_settings_provider.dart';
import '../../providers/tts/tts_model_installation_provider.dart';
import '../../router/app_router.dart';
import '../../services/app_logger.dart';
import '../../services/download/download_failure.dart';
import '../../services/tts/kokoro_model_manager.dart';
import '../../services/tts/tts_engine.dart';
import '../../utils/download_failure_message.dart';

/// 当前 TTS 选中引擎所依赖的本地模型状态。
class TtsPlaybackModelState {
  final TtsEngineKind engine;
  final AsrModelDownloadStatus status;
  final double progress;
  final DownloadFailureKind? failure;

  const TtsPlaybackModelState({
    required this.engine,
    required this.status,
    required this.progress,
    required this.failure,
  });

  bool get isReady =>
      engine == TtsEngineKind.platform ||
      status == AsrModelDownloadStatus.downloaded;
}

/// 从全局 TTS provider 派生当前发音所需模型的单一状态快照。
final ttsPlaybackModelStateProvider = Provider<TtsPlaybackModelState>((ref) {
  final settings = ref.watch(ttsSettingsProvider);
  switch (settings.engine) {
    case TtsEngineKind.platform:
      return const TtsPlaybackModelState(
        engine: TtsEngineKind.platform,
        status: AsrModelDownloadStatus.downloaded,
        progress: 1,
        failure: null,
      );
    case TtsEngineKind.kokoro:
      final state = ref.watch(kokoroModelProvider).of(settings.kokoroVariant);
      return TtsPlaybackModelState(
        engine: settings.engine,
        status: state.downloadStatus,
        progress: state.downloadProgress,
        failure: state.downloadError,
      );
    case TtsEngineKind.piper:
      final state = ref.watch(piperModelProvider).of(settings.activePiperVoice);
      return TtsPlaybackModelState(
        engine: settings.engine,
        status: state.downloadStatus,
        progress: state.downloadProgress,
        failure: state.downloadError,
      );
  }
});

/// 发音前检查当前本地 TTS 模型。
///
/// 返回 true 才允许本次发音；下载中、未下载或失败均只展示全局状态弹窗，返回 false。
Future<bool> ensureTtsModelReadyForPlayback(Ref ref) async {
  await refreshTtsModelInstallStates(ref.read);
  final state = ref.read(ttsPlaybackModelStateProvider);
  if (state.isReady) return true;

  if (state.status == AsrModelDownloadStatus.notDownloaded) {
    _ensureBackgroundDownload(ref, state.engine);
  }
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) return false;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _TtsModelDownloadDialog(),
  );
  return false;
}

/// 只检查指定 TTS 配置是否可用，不弹窗、不下载，供后台 warmup 使用。
Future<bool> isTtsModelReadyForConfig(
  Ref ref, {
  required TtsEngineKind engine,
  KokoroModelVariant? kokoroVariant,
  String? piperVoiceId,
}) async {
  if (engine == TtsEngineKind.platform) return true;
  await refreshTtsModelInstallStates(ref.read);
  final ready = switch (engine) {
    TtsEngineKind.platform => true,
    TtsEngineKind.kokoro =>
      kokoroVariant != null &&
          ref.read(kokoroModelProvider).of(kokoroVariant).isReady,
    TtsEngineKind.piper =>
      piperVoiceId != null &&
          ref.read(piperModelProvider).of(piperVoiceId).isReady,
  };
  AppLogger.log(
    'TtsModelGate',
    '后台配置检查 engine=${engine.diagnosticName} '
        'kokoroVariant=${kokoroVariant?.name} piperVoice=$piperVoiceId ready=$ready',
  );
  return ready;
}

/// 检查指定 TTS 配置所依赖的本地模型，并在缺失时触发下载。
///
/// 只负责模型状态与下载，不弹窗；设置页试听使用此函数，让下载进度继续由
/// 设置页列表展示。普通文本播放若需要弹窗，仍使用 [ensureTtsModelReadyForPlayback]。
Future<bool> ensureTtsModelReadyForConfig(
  Ref ref, {
  required TtsEngineKind engine,
  KokoroModelVariant? kokoroVariant,
  String? piperVoiceId,
}) async {
  AppLogger.log(
    'TtsModelGate',
    '指定配置检查开始 engine=${engine.diagnosticName} '
        'kokoroVariant=${kokoroVariant?.name} piperVoice=$piperVoiceId',
  );
  // 已有内存 ready 状态时同步放行，避免正常试听因重新扫描安装标记产生可见延迟。
  switch (engine) {
    case TtsEngineKind.platform:
      AppLogger.log('TtsModelGate', '指定配置检查结果 ready=true engine=platform');
      return true;
    case TtsEngineKind.kokoro:
      final variant = kokoroVariant;
      if (variant != null &&
          ref.read(kokoroModelProvider).of(variant).isReady) {
        AppLogger.log(
          'TtsModelGate',
          '指定配置检查结果 ready=true source=memory variant=${variant.name}',
        );
        return true;
      }
    case TtsEngineKind.piper:
      final voiceId = piperVoiceId;
      if (voiceId != null && ref.read(piperModelProvider).of(voiceId).isReady) {
        AppLogger.log(
          'TtsModelGate',
          '指定配置检查结果 ready=true source=memory voice=$voiceId',
        );
        return true;
      }
  }
  await refreshTtsModelInstallStates(ref.read);
  switch (engine) {
    case TtsEngineKind.platform:
      AppLogger.log('TtsModelGate', '指定配置刷新后结果 ready=true engine=platform');
      return true;
    case TtsEngineKind.kokoro:
      final variant = kokoroVariant;
      if (variant == null) return false;
      final state = ref.read(kokoroModelProvider).of(variant);
      AppLogger.log(
        'TtsModelGate',
        '指定配置刷新后状态 variant=${variant.name} status=${state.downloadStatus}',
      );
      if (state.isReady) return true;
      if (state.downloadStatus == AsrModelDownloadStatus.notDownloaded) {
        unawaited(
          ref.read(kokoroModelProvider.notifier).ensureDownloaded(variant),
        );
      }
      return false;
    case TtsEngineKind.piper:
      final voiceId = piperVoiceId;
      if (voiceId == null) return false;
      final state = ref.read(piperModelProvider).of(voiceId);
      AppLogger.log(
        'TtsModelGate',
        '指定配置刷新后状态 voice=$voiceId status=${state.downloadStatus}',
      );
      if (state.isReady) return true;
      if (state.downloadStatus == AsrModelDownloadStatus.notDownloaded) {
        unawaited(
          ref.read(piperModelProvider.notifier).ensureDownloaded(voiceId),
        );
      }
      return false;
  }
}

void _ensureBackgroundDownload(Ref ref, TtsEngineKind engine) {
  final settings = ref.read(ttsSettingsProvider);
  switch (engine) {
    case TtsEngineKind.platform:
      return;
    case TtsEngineKind.kokoro:
      unawaited(
        ref
            .read(kokoroModelProvider.notifier)
            .ensureDownloaded(settings.kokoroVariant),
      );
    case TtsEngineKind.piper:
      unawaited(
        ref
            .read(piperModelProvider.notifier)
            .ensureDownloaded(settings.activePiperVoice),
      );
  }
}

class _TtsModelDownloadDialog extends ConsumerWidget {
  const _TtsModelDownloadDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(ttsSettingsProvider);
    final model = switch (settings.engine) {
      TtsEngineKind.platform => const TtsPlaybackModelState(
        engine: TtsEngineKind.platform,
        status: AsrModelDownloadStatus.downloaded,
        progress: 1,
        failure: null,
      ),
      TtsEngineKind.kokoro => _kokoroState(ref, settings),
      TtsEngineKind.piper => _piperState(ref, settings),
    };

    if (model.isReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop();
      });
    }
    final failed = model.status == AsrModelDownloadStatus.failed;
    final progress = '${(model.progress * 100).toStringAsFixed(0)}%';
    return AlertDialog(
      title: Text(failed ? l10n.retryDownload : l10n.ttsModel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failed ? l10n.ttsModelNotDownloaded : progress,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!failed) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: model.progress),
          ],
          if (failed && model.failure != null) ...[
            const SizedBox(height: 8),
            Text(
              downloadFailureMessage(l10n, model.failure),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: failed
          ? [
              FilledButton(
                onPressed: () => _retryDownload(ref, settings.engine),
                child: Text(l10n.retryDownload),
              ),
            ]
          : const [],
    );
  }

  TtsPlaybackModelState _kokoroState(WidgetRef ref, TtsSettings settings) {
    final state = ref.watch(kokoroModelProvider).of(settings.kokoroVariant);
    return TtsPlaybackModelState(
      engine: settings.engine,
      status: state.downloadStatus,
      progress: state.downloadProgress,
      failure: state.downloadError,
    );
  }

  TtsPlaybackModelState _piperState(WidgetRef ref, TtsSettings settings) {
    final state = ref.watch(piperModelProvider).of(settings.activePiperVoice);
    return TtsPlaybackModelState(
      engine: settings.engine,
      status: state.downloadStatus,
      progress: state.downloadProgress,
      failure: state.downloadError,
    );
  }

  void _retryDownload(WidgetRef ref, TtsEngineKind engine) {
    final settings = ref.read(ttsSettingsProvider);
    switch (engine) {
      case TtsEngineKind.platform:
        return;
      case TtsEngineKind.kokoro:
        ref
            .read(kokoroModelProvider.notifier)
            .retryDownload(settings.kokoroVariant);
      case TtsEngineKind.piper:
        ref
            .read(piperModelProvider.notifier)
            .retryDownload(settings.activePiperVoice);
    }
  }
}
