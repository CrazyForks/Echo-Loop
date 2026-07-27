/// 统一的跨平台文本选择样式。
///
/// Flutter 原生端暂不提供可直接读取的系统强调色，因此这里使用各平台的
/// 标准选择蓝，并同时覆盖背景、光标和手柄，避免回落到 App 品牌主题色。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
  static Color backgroundColorOf(BuildContext context) {
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
