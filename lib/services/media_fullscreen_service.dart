import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'window_fullscreen_service.dart';

/// 视频页的跨平台全屏呈现协调器。
///
/// macOS 以原生窗口的实际状态为准；移动端使用 Flutter 官方系统栏和方向 API。
/// 此类由页面创建和销毁，避免系统状态散落在 widget 回调中。
class MediaFullscreenService {
  MediaFullscreenService({WindowFullscreenController? windowService})
    : _windowService = windowService ?? WindowFullscreenService() {
    _windowSubscription = _windowService.changes.listen(
      _handleWindowFullscreenChange,
    );
  }

  final WindowFullscreenController _windowService;
  final _changes = StreamController<bool>.broadcast(sync: true);
  late final StreamSubscription<bool> _windowSubscription;
  bool _isFullscreen = false;
  bool? _macosRequestedFullscreen;

  Stream<bool> get changes => _changes.stream;

  Future<bool> enter({required bool isLandscapeVideo}) async {
    if (kIsWeb) {
      _setFullscreen(true);
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return _enterMacosFullscreen();
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        if (isLandscapeVideo) {
          await SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _setFullscreen(true);
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        _setFullscreen(true);
        return true;
    }
  }

  Future<void> exit() async {
    if (kIsWeb) {
      _setFullscreen(false);
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        await _exitMacosFullscreen();
        return;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        await SystemChrome.setPreferredOrientations(const []);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _setFullscreen(false);
        return;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        _setFullscreen(false);
        return;
    }
  }

  void _setFullscreen(bool value) {
    if (_isFullscreen == value) return;
    _isFullscreen = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  /// 只有视频按钮发起的窗口全屏才展开视频画面。绿色窗口按钮触发的通知仅代表
  /// App 窗口状态，不能改变播放器布局；但视频全屏期间的 Esc 退出仍需收起画面。
  void _handleWindowFullscreenChange(bool fullscreen) {
    if (_macosRequestedFullscreen == fullscreen) {
      _macosRequestedFullscreen = null;
      _setFullscreen(fullscreen);
      return;
    }
    if (!fullscreen && _isFullscreen) _setFullscreen(false);
  }

  Future<bool> _enterMacosFullscreen() async {
    _macosRequestedFullscreen = true;
    final accepted = await _windowService.setFullscreen(true);
    if (!accepted) {
      _macosRequestedFullscreen = null;
      return false;
    }
    // 窗口已经由绿色按钮进入全屏时，原生端不会再发送 didEnter 通知。
    if (_macosRequestedFullscreen == true) {
      _macosRequestedFullscreen = null;
      _setFullscreen(true);
    }
    return true;
  }

  Future<void> _exitMacosFullscreen() async {
    _macosRequestedFullscreen = false;
    final accepted = await _windowService.setFullscreen(false);
    if (!accepted) {
      _macosRequestedFullscreen = null;
      return;
    }
    if (_macosRequestedFullscreen == false) {
      _macosRequestedFullscreen = null;
      _setFullscreen(false);
    }
  }

  Future<void> dispose() async {
    await _windowSubscription.cancel();
    await _changes.close();
    await _windowService.dispose();
  }
}
