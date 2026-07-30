/// 自有选区实现的移动端长按反馈。
///
/// 手势完全由 `SelectableContent` 自己识别，框架不会代发任何反馈，因此这里一次性
/// 发齐平台标准序列（轻量选择反馈 + 长按反馈），与官方 `SelectableText` /
/// `SelectionArea` 的最终反馈序列一致。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 选区触感/音效反馈。
abstract final class PlatformSelectionFeedback {
  /// 长按建立选区时的反馈（桌面平台不发）。
  static void forOwnedLongPressSelection(BuildContext context) {
    if (!_isMobilePlatform) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(Feedback.forLongPress(context));
  }

  static bool get _isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
