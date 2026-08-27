import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/services/tts/piper_model_catalog.dart';
import 'package:echo_loop/services/tts/tts_engine.dart';

void main() {
  test('目录包含 9 个 Piper 模型，且规格完整', () {
    expect(piperVoices, hasLength(9));
    expect(piperVoicesByAccent(TtsAccent.us), hasLength(6));
    expect(piperVoicesByAccent(TtsAccent.uk), hasLength(3));
    expect(piperVoices.map((voice) => voice.id).toSet(), hasLength(9));
    for (final voice in piperVoices) {
      expect(voice.archivePath, endsWith('.tar.gz'));
      expect(voice.sha256, hasLength(64));
      expect(voice.estimatedDownloadBytes, greaterThan(0));
    }
  });

  test('默认音色按口音匹配', () {
    expect(piperDefaultVoice(TtsAccent.us).id, piperDefaultVoiceUs);
    expect(piperDefaultVoice(TtsAccent.uk).id, piperDefaultVoiceUk);
  });

  test('未知音色查询返回 null', () {
    expect(piperVoiceById('not_a_voice'), isNull);
  });
}
