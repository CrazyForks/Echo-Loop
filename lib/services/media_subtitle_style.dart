import 'package:flutter/widgets.dart';

/// 视频画面字幕样式参数。
///
/// 字幕由 media_kit 叠加在视频纹理上，字号必须按画面视口计算；手机和小窗
/// 应维持常规 12-16 号区间，全屏时再适度放大。
class MediaSubtitleStyle {
  const MediaSubtitleStyle({
    required this.fontSize,
    required this.horizontalPadding,
    required this.bottomPadding,
  });

  final double fontSize;
  final double horizontalPadding;
  final double bottomPadding;

  /// 根据视频画面尺寸生成可读字幕样式。
  ///
  /// 以画面高度驱动字号，避免宽屏视频仅因横向很宽就把字幕放得过大。
  factory MediaSubtitleStyle.forViewport(Size viewportSize) {
    final width = _finitePositive(viewportSize.width);
    final height = _finitePositive(viewportSize.height);
    return MediaSubtitleStyle(
      fontSize: _clamp(height * 0.035, 12.0, 24.0),
      horizontalPadding: _clamp(width * 0.025, 8.0, 24.0),
      bottomPadding: _clamp(height * 0.045, 10.0, 28.0),
    );
  }
}

double _finitePositive(double value) {
  if (!value.isFinite || value <= 0) return 1;
  return value;
}

double _clamp(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}
