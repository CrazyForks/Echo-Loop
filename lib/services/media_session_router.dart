import 'package:audio_service/audio_service.dart';

/// 全 App 唯一接入 `audio_service` 的系统媒体会话路由器。
///
/// `audio_service` 不是实际的解码播放器；它把当前媒体 handler 暴露给系统，
/// 让锁屏、通知栏、蓝牙耳机等系统媒体控制知道由谁接收播放操作。
/// 本路由器在默认音频 handler 与视频 handler 之间切换这份系统媒体会话，
/// 避免把“系统媒体控制”误解为“只能服务音频播放”。
class MediaSessionRouter extends SwitchAudioHandler {
  MediaSessionRouter({required AudioHandler defaultHandler})
    : _defaultHandler = defaultHandler,
      super(defaultHandler);

  final AudioHandler _defaultHandler;

  /// 当前媒体会话是否被非默认 handler（视频链路）占用。
  bool get isRouted => inner != _defaultHandler;

  /// 把系统媒体会话切给 [handler]。幂等。
  void activate(AudioHandler handler) {
    if (inner == handler) return;
    inner = handler;
  }

  /// [handler] 交还媒体会话给默认 handler。旧页面迟到的 deactivate 不会误切走新占用者。
  void deactivate(AudioHandler handler) {
    if (inner != handler) return;
    inner = _defaultHandler;
  }
}
