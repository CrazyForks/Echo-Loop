import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sense_group_range_playback.dart';
import 'audio_engine/audio_engine_provider.dart';
import 'audio_engine/audio_engine_sense_group_range_playback.dart';

/// 讲解组件的区间播放入口。
///
/// 默认使用媒体播放器；前台复习或视频会话在页面子树通过 override 选择自身实现。
final senseGroupRangePlaybackProvider = Provider<SenseGroupRangePlayback>(
  (ref) => AudioEngineSenseGroupRangePlayback(
    engine: ref.read(audioEngineProvider.notifier),
    playbackSpeed: () => 1.0,
  ),
);
