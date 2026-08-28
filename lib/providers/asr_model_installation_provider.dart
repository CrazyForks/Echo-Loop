import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'asr_model_installation_gate.dart';
import 'offline_asr_settings_provider.dart';

/// ASR 安装状态 Gate；语义与 TTS Gate 相同，磁盘扫描只在需要时单飞执行。
final asrModelInstallationGateProvider = Provider<AsrModelInstallationGate>((
  ref,
) {
  late final AsrModelInstallationGate gate;
  gate = AsrModelInstallationGate(
    ({required shouldCommit}) => ref
        .read(offlineAsrSettingsProvider.notifier)
        .refreshInstalledStates(shouldCommit: shouldCommit),
  );
  ref.listen<OfflineAsrSettingsState>(offlineAsrSettingsProvider, (
    before,
    after,
  ) {
    if (before == null || gate.isLoading) return;
    final removed = before.modelStates.entries.any(
      (entry) => entry.value.isReady && !after.modelStateOf(entry.key).isReady,
    );
    if (removed) gate.invalidate();
  });
  return gate;
});
