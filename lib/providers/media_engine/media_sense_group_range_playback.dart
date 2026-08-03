import '../../models/sense_group_range_playback.dart';
import 'media_engine_provider.dart';

/// 基于 [MediaEngine] 的意群区间播放实现。
///
/// 每个学习会话各自创建实例；内部 generation 与 MediaEngine session 双重隔离，
/// 防止重复点击、切句或退出后的旧播放影响当前材料。
class MediaSenseGroupRangePlayback implements SenseGroupRangePlayback {
  MediaSenseGroupRangePlayback({
    required MediaEngine engine,
    required double Function() playbackSpeed,
  }) : _engine = engine,
       _playbackSpeed = playbackSpeed;

  final MediaEngine _engine;
  final double Function() _playbackSpeed;
  int _generation = 0;

  @override
  Future<void> play(Duration start, Duration end) async {
    final generation = ++_generation;
    final sessionId = _engine.newSession();
    await _engine.setSpeed(_playbackSpeed());
    if (generation != _generation || !_engine.isActiveSession(sessionId)) {
      return;
    }
    await _engine.playRangeOnce(start, end, sessionId);
  }

  @override
  Future<void> cancel() async {
    _generation++;
    await _engine.pause();
  }
}
