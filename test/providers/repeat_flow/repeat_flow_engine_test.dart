import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/models/sentence.dart';
import 'package:echo_loop/providers/repeat_flow/repeat_flow_engine.dart';
import 'package:echo_loop/providers/repeat_flow/repeat_flow_phase.dart';
import 'package:echo_loop/providers/repeat_flow/repeat_flow_state.dart';

void main() {
  test('无评分但有录音文件时保留录音并继续流程', () async {
    var clearRecordingCalls = 0;
    RepeatFlowState? latestState;
    final engine = RepeatFlowEngine(
      onStateChanged: (state) => latestState = state,
      callbacks: RepeatFlowCallbacks(
        pauseAudio: () {},
        playSentence: (_, _) async {},
        startRecording:
            ({
              required promptId,
              required referenceText,
              required maxDuration,
              referenceDuration,
            }) {},
        cancelRecording: () async {},
        stopAndEvaluate: ({required referenceText}) async {},
        clearRecording: () => clearRecordingCalls += 1,
        setMaxRecordingDuration: (_) {},
        hasDetectedSpeech: () => true,
      ),
    );
    engine.prepare(
      sentences: [
        Sentence(
          index: 0,
          text: 'Practice this sentence.',
          startTime: Duration.zero,
          endTime: const Duration(seconds: 1),
        ),
      ],
      config: RepeatFlowConfig(
        audioItemId: 'audio-1',
        getRepeatCount: (_) => 1,
        getIntervalDuration: (_) => const Duration(seconds: 30),
        isManualMode: () => false,
      ),
    );

    await engine.startPlaying();
    expect(latestState?.phase, isA<Recording>());

    engine.onRecordingFinished('/tmp/recording.m4a', null);

    expect(latestState?.recordingPath, '/tmp/recording.m4a');
    expect(latestState?.recordingScore, isNull);
    expect(latestState?.phase, isA<WaitingInterval>());
    expect(clearRecordingCalls, 0);
  });
}
