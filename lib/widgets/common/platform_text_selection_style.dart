/// 统一的跨平台文本选择样式。
///
/// Flutter 原生端暂不提供可直接读取的系统强调色，因此这里使用各平台的
/// 标准选择蓝，并同时覆盖背景、光标和手柄，避免回落到 App 品牌主题色。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 为子树提供与 App 品牌主题解耦的平台标准文本选择样式。
class PlatformTextSelectionStyle extends StatelessWidget {
  const PlatformTextSelectionStyle({super.key, required this.child});

  final Widget child;

  /// 平台标准选择强调色，用于光标和选择手柄。
  static Color accentColorOf(BuildContext context) {
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => CupertinoColors.systemBlue.resolveFrom(context),
      TargetPlatform.android || TargetPlatform.fuchsia => Colors.blue,
      TargetPlatform.windows => const Color(0xFF0078D4),
      TargetPlatform.linux => const Color(0xFF3584E4),
    };
  }

  /// 平台标准选择背景色；Apple 使用 Cupertino 原生透明度，其余沿用 Material。
  ///
  /// 深色主题下页面背景接近纯黑，同一套「强调色 × 低透明度」叠加后与背景
  /// 几乎无法区分（实测对比度约 1.4:1，选区形同隐形），因此深色主题统一改用
  /// 更亮的强调蓝并提高不透明度，与 [AppTheme.navActiveColor] 选中态色呼应。
  static Color backgroundColorOf(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return AppTheme.navActiveColor.withValues(alpha: 0.6);
    }
    final accent = accentColorOf(context);
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => accent.withValues(alpha: 0.2),
      _ => accent.withValues(alpha: 0.4),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColorOf(context);
    final background = backgroundColorOf(context);
    return Theme(
      data: theme.copyWith(
        textSelectionTheme: theme.textSelectionTheme.copyWith(
          cursorColor: accent,
          selectionColor: background,
          selectionHandleColor: accent,
        ),
      ),
      child: CupertinoTheme(
        data: CupertinoTheme.of(context).copyWith(selectionHandleColor: accent),
        child: DefaultSelectionStyle(
          cursorColor: accent,
          selectionColor: background,
          child: child,
        ),
      ),
    );
  }
}
