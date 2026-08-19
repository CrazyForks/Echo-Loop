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
import '../../router/app_router.dart';
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
    case TtsEngineKind.echoLoop:
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

void _ensureBackgroundDownload(Ref ref, TtsEngineKind engine) {
  final settings = ref.read(ttsSettingsProvider);
  switch (engine) {
    case TtsEngineKind.platform:
      return;
    case TtsEngineKind.echoLoop:
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
      TtsEngineKind.echoLoop => _kokoroState(ref, settings),
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
      case TtsEngineKind.echoLoop:
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
