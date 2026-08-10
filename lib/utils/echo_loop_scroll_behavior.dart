import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Echo Loop 的全局滚动手势策略。
///
/// macOS 触控板偶发上报乱序的 PointerPanZoom 时间戳。Flutter 默认的
/// [MacOSScrollViewFlingVelocityTracker] 会对此触发 debug 断言并中断滚动；
/// 因此 macOS 使用不要求时间戳单调递增的通用 [VelocityTracker]。
class EchoLoopScrollBehavior extends MaterialScrollBehavior {
  const EchoLoopScrollBehavior();

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    if (getPlatform(context) == TargetPlatform.macOS) {
      return (PointerEvent event) => VelocityTracker.withKind(event.kind);
    }
    return super.velocityTrackerBuilder(context);
  }
}
