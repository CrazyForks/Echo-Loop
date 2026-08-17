import '../../models/sense_group_range_playback.dart';
import 'media_engine_provider.dart';

/// 基于 [MediaEngine] 的意群区间播放实现。
///
/// 每个学习会话各自创建实例；内部 generation 与活动标记隔离，
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
  bool _isPlaying = false;

  @override
  Future<void> play(Duration start, Duration end) async {
    final generation = ++_generation;
    _isPlaying = true;
    try {
      await _engine.playRange(start, end, speed: _playbackSpeed());
    } finally {
      if (generation == _generation) {
        _isPlaying = false;
      }
    }
  }

  @override
  Future<void> cancel() async {
    _generation++;
    // 页面切句会清理每个 SentenceExplanationView，即使用户从未点过意群。
    // 此时不得暂停共享 MediaEngine 的主句 range，否则会误取消自动跟读。
    if (!_isPlaying) return;
    _isPlaying = false;
    await _engine.cancelActiveRange(reason: 'sense-group-cancel');
  }
}
