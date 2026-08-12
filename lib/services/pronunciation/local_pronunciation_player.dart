import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../app_logger.dart';

/// 短音频播放器后端，测试可注入 fake。
abstract interface class PronunciationPlayerBackend {
  Stream<void> get completed;
  Stream<String> get errors;
  Future<void> open(String filePath);
  Future<void> stop();
  Future<void> dispose();
}

class MediaKitPronunciationPlayerBackend implements PronunciationPlayerBackend {
  MediaKitPronunciationPlayerBackend() : _player = Player();
  final Player _player;

  @override
  Stream<void> get completed =>
      _player.stream.completed.where((value) => value).map((_) {});

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(String filePath) =>
      _player.open(Media(filePath), play: true);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// 调用方无状态的本地发音播放服务。
class LocalPronunciationPlayer {
  LocalPronunciationPlayer({PronunciationPlayerBackend? backend})
    : _backend = backend ?? MediaKitPronunciationPlayerBackend();

  final PronunciationPlayerBackend _backend;
  int _sessionId = 0;

  /// 播放文件直到完成。新播放或 stop 会使旧 await 失效。
  Future<bool> playFile(String filePath) async {
    final sessionId = ++_sessionId;
    try {
      await _backend.stop();
      if (sessionId != _sessionId) return false;
      AppLogger.log(
        'PronunciationPlayer',
        '▶ open sid=$sessionId path=$filePath',
      );
      await _backend.open(filePath);
      if (sessionId != _sessionId) return false;
      final outcome = await Future.any<Object>([
        _backend.completed.first.then<Object>((_) => true),
        _backend.errors.first.then<Object>((message) => StateError(message)),
      ]);
      if (outcome is Error || outcome is Exception) throw outcome;
      return sessionId == _sessionId;
    } catch (error, stackTrace) {
      AppLogger.log(
        'PronunciationPlayer',
        'play failed path=$filePath error=$error\n$stackTrace',
      );
      return false;
    }
  }

  Future<void> stop() async {
    _sessionId++;
    await _backend.stop();
  }

  Future<void> dispose() async {
    _sessionId++;
    await _backend.dispose();
  }
}
