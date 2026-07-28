import 'package:audio_service/audio_service.dart';

/// 全 App 唯一注册进 AudioService 的 handler：在默认音频 handler 与视频 handler
/// 之间切换系统媒体会话（锁屏/通知栏归属）。
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
