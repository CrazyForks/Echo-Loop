import '../../models/sense_group_range_playback.dart';
import 'foreground_audio_engine_provider.dart';

/// 收藏与录音类任务的意群播放实现。
///
/// 区间播放前由 [ForegroundAudioEngine] 自动确认材料已加载；UI 不需要也不能
/// 预先管理播放器状态。generation 让取消/重复点击后的旧异步调用失效。
class ForegroundSenseGroupRangePlayback implements SenseGroupRangePlayback {
  ForegroundSenseGroupRangePlayback({
    required ForegroundAudioEngine engine,
    required double Function() playbackSpeed,
  }) : _engine = engine,
       _playbackSpeed = playbackSpeed;

  final ForegroundAudioEngine _engine;
  final double Function() _playbackSpeed;
  int _generation = 0;

  @override
  Future<void> play(String audioItemId, Duration start, Duration end) async {
    final generation = ++_generation;
    await _engine.playRangeForAudio(
      audioItemId,
      start,
      end,
      speed: _playbackSpeed(),
    );
    if (generation != _generation) return;
  }

  @override
  Future<void> cancel() async {
    _generation++;
    await _engine.pause();
  }
}
