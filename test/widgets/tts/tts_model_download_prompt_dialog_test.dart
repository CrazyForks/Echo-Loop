import 'package:echo_loop/providers/tts/kokoro_model_provider.dart';
import 'package:echo_loop/providers/tts/piper_model_provider.dart';
import 'package:echo_loop/providers/tts/tts_settings_provider.dart';
import 'package:echo_loop/services/tts/kokoro_model_manager.dart';
import 'package:echo_loop/services/tts/tts_engine.dart';
import 'package:echo_loop/widgets/tts/tts_model_download_prompt_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Advanced 发音状态复用当前 Kokoro 全局下载进度', () {
    final container = ProviderContainer(
      overrides: [
        initialTtsSettingsProvider.overrideWithValue(
          const TtsSettings(engine: TtsEngineKind.kokoro),
        ),
        initialKokoroModelStateProvider.overrideWithValue(
          const KokoroModelsState({
            KokoroModelVariant.fp32: KokoroModelState(
              downloadStatus: AsrModelDownloadStatus.downloading,
              downloadProgress: 0.42,
            ),
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(ttsPlaybackModelStateProvider);

    expect(state.engine, TtsEngineKind.kokoro);
    expect(state.status, AsrModelDownloadStatus.downloading);
    expect(state.progress, 0.42);
    expect(state.isReady, isFalse);
  });

  test('Balanced 发音状态复用当前 Piper 全局失败状态', () {
    const voiceId = 'en_US-amy-medium';
    final container = ProviderContainer(
      overrides: [
        initialTtsSettingsProvider.overrideWithValue(
          const TtsSettings(engine: TtsEngineKind.piper),
        ),
        initialPiperModelStateProvider.overrideWithValue(
          const PiperModelsState({
            voiceId: PiperModelState(
              downloadStatus: AsrModelDownloadStatus.failed,
            ),
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(ttsPlaybackModelStateProvider);

    expect(state.engine, TtsEngineKind.piper);
    expect(state.status, AsrModelDownloadStatus.failed);
    expect(state.isReady, isFalse);
  });
}
