import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 学习任务简报的统一内容容器。
///
/// 所有学习任务只在这里处理底部系统安全区，避免不同简报分别叠加或遗漏
/// 导航栏 / Home Indicator 间距。
class LearningBriefingSheetContent extends StatelessWidget {
  /// 简报主体内容。
  final Widget child;

  const LearningBriefingSheetContent({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: true,
      maintainBottomViewPadding: true,
      // 仅保留轻量视觉留白；真实系统安全区仍由 SafeArea 完整接管。
      minimum: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          AppSpacing.l,
          AppSpacing.l,
          0,
        ),
        child: child,
      ),
    );
  }
}
