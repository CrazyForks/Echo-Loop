/// 统一 `SelectionArea` 与 `SelectableText` 的移动端长按反馈。
///
/// Flutter 3.41 的两套官方选区底层反馈不一致：`SelectionArea` 固定发送
/// `selectionClick`，`SelectableText` 固定发送平台长按反馈。这里仅补齐另一半，
/// 不接管手势识别和选区绘制，使两处最终反馈序列一致。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 官方文本选择组件之间的反馈差异协调器。
abstract final class PlatformSelectionFeedback {
  /// `SelectionArea` 已发送轻量选择反馈；补发平台标准长按反馈。
  static void completeSelectableRegionLongPress(BuildContext context) {
    if (!_isMobilePlatform) return;
    unawaited(Feedback.forLongPress(context));
  }

  /// `SelectableText` 将发送平台长按反馈；先补发轻量选择反馈。
  ///
  /// iOS 首次未聚焦长按是 Flutter 的特殊分支，不会发送标准长按反馈，因此由这里
  /// 一并补齐；已聚焦时仍交给框架发送，避免重复震动。
  static void completeEditableTextLongPress(
    BuildContext context, {
    required bool hadFocusOnPointerDown,
  }) {
    if (!_isMobilePlatform) return;
    unawaited(HapticFeedback.selectionClick());
    if (defaultTargetPlatform == TargetPlatform.iOS && !hadFocusOnPointerDown) {
      unawaited(Feedback.forLongPress(context));
    }
  }

  static bool get _isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
