/// 通用单文件音频播放服务。
///
/// 封装 just_audio 的 [AudioPlayer]，提供简洁的 play/stop API。
/// [play] 返回 Future，播放完成或 [stop] 时 complete。
///
/// 只负责「播」，不持有面向 UI 的播放状态：UI 状态由 [AudioPreviewController]
/// 基于 [play] 的 Future 维护，这样测试替身覆写 [play] 也不会丢状态。
library;

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'app_logger.dart';

/// 通用单文件音频播放服务。
class AudioPlaybackService {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  String? _currentFilePath;
  Completer<void> _playCompleter = Completer<void>()..complete();
  bool _isDisposed = false;

  /// 播放音频文件，返回 Future 在播放完成或被 [stop] 时 complete。
  Future<void> play(String filePath) async {
    if (_isDisposed) {
      AppLogger.log('AudioPlayback', '播放失败: service 已释放 path=$filePath');
      throw StateError('AudioPlaybackService has been disposed');
    }

    // 停止当前播放
    if (_player != null) {
      await _player!.stop();
    }
    // 结束旧的 Future
    if (!_playCompleter.isCompleted) {
      _playCompleter.complete();
    }
    _playCompleter = Completer<void>();

    final player = await _ensurePlayer();
    _currentFilePath = filePath;
    AppLogger.log('AudioPlayback', '开始播放: path=$filePath');
    try {
      await player.setFilePath(filePath);
      await player.play();
    } catch (error) {
      // 起播失败必须把状态收回来，否则 UI 永久停在「正在播放」。
      AppLogger.log('AudioPlayback', '起播失败: path=$filePath error=$error');
      _currentFilePath = null;
      if (!_playCompleter.isCompleted) {
        _playCompleter.complete();
      }
      rethrow;
    }

    return _playCompleter.future;
  }

  /// 停止播放。
  Future<void> stop() async {
    if (_isDisposed) {
      AppLogger.log('AudioPlayback', '停止播放跳过: service 已释放');
      return;
    }

    AppLogger.log('AudioPlayback', '停止播放: path=$_currentFilePath');
    _currentFilePath = null;
    if (_player != null) {
      await _player!.stop();
    }
    if (!_playCompleter.isCompleted) {
      _playCompleter.complete();
    }
  }

  /// 释放资源。
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    AppLogger.log('AudioPlayback', '释放播放服务: path=$_currentFilePath');
    await _playerStateSub?.cancel();
    _playerStateSub = null;
    if (_player != null) {
      await _player!.dispose();
      _player = null;
    }
    _currentFilePath = null;
    if (!_playCompleter.isCompleted) {
      _playCompleter.complete();
    }
  }

  /// 懒初始化播放器。
  Future<AudioPlayer> _ensurePlayer() async {
    if (_isDisposed) {
      throw StateError('AudioPlaybackService has been disposed');
    }
    if (_player != null) return _player!;

    final player = AudioPlayer();
    _player = player;
    _playerStateSub = player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        AppLogger.log('AudioPlayback', '播放完成: path=$_currentFilePath');
        _currentFilePath = null;
        if (!_playCompleter.isCompleted) {
          _playCompleter.complete();
        }
      }
    });
    return player;
  }
}
