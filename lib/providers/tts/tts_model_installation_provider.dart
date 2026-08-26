import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_logger.dart';
import 'kokoro_model_provider.dart';
import 'piper_model_provider.dart';

/// 检查全部 TTS 模型的安装标记，并同步到本次进程的内存状态。
///
/// 这是 TTS 模型安装状态的统一检查入口；只读取各模型目录中的
/// `install.json`，不会触发下载。
Future<void> refreshTtsModelInstallStates(
  T Function<T>(ProviderListenable<T>) read,
) async {
  AppLogger.log('TtsModelGate', '开始刷新 Kokoro/Piper 安装状态');
  await Future.wait([
    read(kokoroModelProvider.notifier).refreshInstalledStates(),
    read(piperModelProvider.notifier).refreshInstalledStates(),
  ]);
  AppLogger.log('TtsModelGate', '完成刷新 Kokoro/Piper 安装状态');
}
