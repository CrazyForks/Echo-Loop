import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/models/sentence.dart';
import 'package:echo_loop/providers/blind_flow/blind_practice_flow_engine.dart';
import 'package:echo_loop/providers/blind_flow/blind_practice_flow_phase.dart';

void main() {
  test('旧播放取消后不跳过用户切换到的下一句', () async {
    final firstResult = Completer<bool>();
    final started = Completer<void>();
    final playedIndices = <int>[];
    final engine = BlindPracticeFlowEngine(
      onStateChanged: (_) {},
      callbacks: BlindPracticeFlowCallbacks(
        pauseAudio: () {},
        playSentence: (sentence, _) async {
          playedIndices.add(sentence.index);
          if (sentence.index == 0) {
            started.complete();
            return firstResult.future;
          }
          return true;
        },
      ),
    );
    engine.prepare(sentences: _sentences(), config: _manualConfig());

    final initialPlay = engine.startPlaying();
    await started.future;
    await engine.nextSentence();
    firstResult.complete(false);
    await initialPlay;

    expect(engine.state.sentenceIndex, 1);
    expect(engine.state.phase, isA<BlindWaitingForUser>());
    expect(playedIndices, [0, 1]);
  });

  test('旧播放取消后不跳过用户切换到的上一句', () async {
    final firstResult = Completer<bool>();
    final started = Completer<void>();
    final playedIndices = <int>[];
    final engine = BlindPracticeFlowEngine(
      onStateChanged: (_) {},
      callbacks: BlindPracticeFlowCallbacks(
        pauseAudio: () {},
        playSentence: (sentence, _) async {
          playedIndices.add(sentence.index);
          if (sentence.index == 1) {
            started.complete();
            return firstResult.future;
          }
          return true;
        },
      ),
    );
    engine.prepare(
      sentences: _sentences(),
      startIndex: 1,
      config: _manualConfig(),
    );

    final initialPlay = engine.startPlaying();
    await started.future;
    await engine.previousSentence();
    firstResult.complete(false);
    await initialPlay;

    expect(engine.state.sentenceIndex, 0);
    expect(engine.state.phase, isA<BlindWaitingForUser>());
    expect(playedIndices, [1, 0]);
  });

  test('当前 flow 播放失败时仍跳过不可播放句', () async {
    final engine = BlindPracticeFlowEngine(
      onStateChanged: (_) {},
      callbacks: BlindPracticeFlowCallbacks(
        pauseAudio: () {},
        playSentence: (sentence, _) async => sentence.index != 0,
      ),
    );
    engine.prepare(sentences: _sentences(), config: _manualConfig());

    await engine.startPlaying();

    expect(engine.state.sentenceIndex, 1);
    expect(engine.state.phase, isA<BlindWaitingForUser>());
  });

  test('最后一句播放中暂停后，取消结果不会完成流程', () async {
    final playbackResult = Completer<bool>();
    final started = Completer<void>();
    final engine = BlindPracticeFlowEngine(
      onStateChanged: (_) {},
      callbacks: BlindPracticeFlowCallbacks(
        pauseAudio: () {},
        playSentence: (_, _) async {
          started.complete();
          return playbackResult.future;
        },
      ),
    );
    engine.prepare(sentences: [_sentences().last], config: _manualConfig());

    final playing = engine.startPlaying();
    await started.future;
    engine.enterWaitingForUser();
    playbackResult.complete(false);
    await playing;

    expect(engine.state.sentenceIndex, 0);
    expect(engine.state.phase, isA<BlindWaitingForUser>());
  });
}

BlindPracticeFlowConfig _manualConfig() => BlindPracticeFlowConfig(
  getRepeatCount: (_) => 1,
  getRepeatIntervalDuration: (_) => Duration.zero,
  getSentenceIntervalDuration: (_) => Duration.zero,
  isManualMode: () => true,
);

List<Sentence> _sentences() => [
  Sentence(
    index: 0,
    text: 'First sentence.',
    startTime: Duration.zero,
    endTime: const Duration(seconds: 1),
  ),
  Sentence(
    index: 1,
    text: 'Second sentence.',
    startTime: const Duration(seconds: 1),
    endTime: const Duration(seconds: 2),
  ),
];
