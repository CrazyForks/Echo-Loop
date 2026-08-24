/// 应用级用户通知：供没有页面上下文的服务统一向根 UI 报告问题。
library;

import 'dart:async';

/// 用户可见消息的稳定标识；新增全局服务时可复用同一总线。
enum AppNoticeMessage { playbackFailed }

/// 通知展示方式。当前全局错误使用对话框，模型保留扩展空间。
enum AppNoticePresentation { dialog }

class AppNotice {
  const AppNotice({
    required this.message,
    required this.dedupeKey,
    this.presentation = AppNoticePresentation.dialog,
  });

  final AppNoticeMessage message;
  final String dedupeKey;
  final AppNoticePresentation presentation;
}

/// 全局通知总线不依赖 Widget，后台服务也可安全发布通知。
class AppNoticeBus {
  final StreamController<AppNotice> _controller =
      StreamController<AppNotice>.broadcast();

  Stream<AppNotice> get notices => _controller.stream;

  void publish(AppNotice notice) => _controller.add(notice);
}

final appNoticeBus = AppNoticeBus();
