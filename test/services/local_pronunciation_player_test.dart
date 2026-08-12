import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/services/pronunciation/local_pronunciation_player.dart';

class _FakeBackend implements PronunciationPlayerBackend {
  final completedController = StreamController<void>.broadcast();
  final errorController = StreamController<String>.broadcast();
  final opened = <String>[];
  int stops = 0;

  @override
  Stream<void> get completed => completedController.stream;
  @override
  Stream<String> get errors => errorController.stream;
  @override
  Future<void> open(String filePath) async => opened.add(filePath);
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {
    await completedController.close();
    await errorController.close();
  }
}

void main() {
  test('playFile waits for completion and reuses one backend', () async {
    final backend = _FakeBackend();
    final player = LocalPronunciationPlayer(backend: backend);
    final result = player.playFile('/audio/read.opus');
    await Future<void>.delayed(Duration.zero);
    expect(backend.opened, ['/audio/read.opus']);
    backend.completedController.add(null);
    expect(await result, isTrue);
    expect(backend.stops, 1);
    await player.dispose();
  });

  test('backend error returns false for TTS fallback', () async {
    final backend = _FakeBackend();
    final player = LocalPronunciationPlayer(backend: backend);
    final result = player.playFile('/audio/broken.opus');
    await Future<void>.delayed(Duration.zero);
    backend.errorController.add('decode failed');
    expect(await result, isFalse);
    await player.dispose();
  });
}
