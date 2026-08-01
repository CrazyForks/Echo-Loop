/// 单个音频文件的试听状态编排。
///
/// 「播一个本地文件、UI 显示播放/停止图标」是多处共用的通用能力（录音回放 badge、
/// 复述评估弹窗等）。本类是这一能力的唯一实现：把 [AudioPlaybackService.play] 的
/// Future 生命周期翻译成一个可观察的布尔状态，让 UI 只做展示。
///
/// 设计要点：
/// 1. **状态跟着 Future 走**，不查播放器内部状态。just_audio 的 `playing` 表示播放
///    意图，播到 `completed` 后仍为 true，任何「问播放器现在在不在播」的写法都会把
///    播完误判成在播。
/// 2. **状态用 [ValueListenable] 暴露**，不用流。它随时可读当前值，滑出视口被回收的
///    widget 重建后能立刻拿到正确状态，不依赖「订阅期间是否错过事件」。
/// 3. **组合而非继承 service**，所以测试替身覆写 `play`/`stop` 时状态依旧正确。
/// 4. 一个 controller 一份状态。需要多处 UI 状态一致（如自动回放与 badge 图标）时，
///    共享同一个 controller 实例，而不是各建一个。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'audio_playback_service.dart';

/// 单文件试听控制器。
class AudioPreviewController {
  /// [service] 由外部注入时，其生命周期归注入方；controller 只在自建时负责释放。
  AudioPreviewController({AudioPlaybackService? service})
    : _service = service ?? AudioPlaybackService(),
      _ownsService = service == null;

  final AudioPlaybackService _service;
  final bool _ownsService;
  final ValueNotifier<bool> _isPlaying = ValueNotifier<bool>(false);

  /// 同一次播放的标识。
  ///
  /// 播放期间若发生停止或换文件，旧的 `await play` 返回后不得再改状态，
  /// 否则会把新一次播放的状态覆盖成「已停止」。
  int _generation = 0;
  bool _isDisposed = false;

  /// 播放状态，供 UI 观察。
  ValueListenable<bool> get isPlayingListenable => _isPlaying;

  /// 当前是否正在播放。
  bool get isPlaying => _isPlaying.value;

  /// 播放指定文件，Future 在播放自然结束或被 [stop] 打断时返回。
  ///
  /// 返回本次是否播到了结束：失败、被打断、以及「已在播放而跳过本次」都返回 false。
  /// 播放失败在这里就地记录并消化掉，不向上抛：调用方多是点击回调，无处接管异常；
  /// 需要区分成功与失败时读返回值，不要依赖 try/catch。
  Future<bool> play(String filePath) async {
    if (_isDisposed || _isPlaying.value) return false;

    final generation = ++_generation;
    _isPlaying.value = true;
    try {
      await _service.play(filePath);
      // 播放期间被 stop 或换文件取代时，不算播到结束。
      return !_isDisposed && generation == _generation;
    } catch (error) {
      AppLogger.log('AudioPreview', '试听失败: path=$filePath error=$error');
      return false;
    } finally {
      // 这次播放已被后续操作取代时不要回写状态。
      if (!_isDisposed && generation == _generation) {
        _isPlaying.value = false;
      }
    }
  }

  /// 停止播放。未在播放时也可安全调用。
  Future<void> stop() async {
    if (_isDisposed) return;

    _generation += 1;
    _isPlaying.value = false;
    await _service.stop();
  }

  /// 在播则停、未播则播。
  Future<void> toggle(String filePath) async {
    if (_isPlaying.value) {
      await stop();
      return;
    }
    await play(filePath);
  }

  /// 释放资源。自建的 service 一并释放，注入的不动。
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _generation += 1;
    _isPlaying.dispose();
    if (_ownsService) await _service.dispose();
  }
}
