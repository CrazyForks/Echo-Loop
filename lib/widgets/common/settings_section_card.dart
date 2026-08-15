/// 设置类底部弹窗的分组卡片容器。
///
/// 用背景色块（+深色描边）将一组相关设置项从弹窗其它内容中视觉隔离出来，
/// 替代仅靠间距和文字加粗表达层级的旧写法。容器只负责纵向 padding，
/// 横向留白由内部各行控件自身的 `contentPadding`/`tilePadding` 负责。
library;

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 设置分组卡片。
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({super.key, this.title, required this.children});

  /// 分组标题，不传则不渲染标题行（用于紧邻弹窗标题的第一个分组）。
  final String? title;

  /// 分组内的设置行。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      decoration: BoxDecoration(
        color: AppTheme.settingsSectionBackground(theme.brightness),
        borderRadius: BorderRadius.circular(16),
        border: isLight
            ? null
            : Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.m,
                AppSpacing.s,
                AppSpacing.m,
                AppSpacing.s,
              ),
              child: Text(title!, style: AppTextStyles.sectionHeader(context)),
            ),
          ...children,
        ],
      ),
    );
  }
}
