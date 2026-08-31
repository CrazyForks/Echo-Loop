/// 学习任务设置弹窗的公共布局骨架。
///
/// 固定标题和关闭入口，仅让设置内容滚动，避免内容较长时用户失去关闭弹窗
/// 的入口；弹窗高度同时限制为屏幕高度的 80%。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 提供统一的设置弹窗头部、最大高度和内容滚动区域。
class SettingsSheetScaffold extends StatelessWidget {
  /// 创建设置弹窗骨架。
  const SettingsSheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.closeButtonKey,
    required this.child,
  });

  /// 弹窗标题。
  final String title;

  /// 标题下方的辅助说明；为空时不渲染说明行。
  final String? subtitle;

  /// 关闭按钮测试标识。
  final Key? closeButtonKey;

  /// 可滚动的设置内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.s,
            AppSpacing.l,
            AppSpacing.l,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.m),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: closeButtonKey ?? const Key('settings-sheet-close'),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.l),
              ] else
                const SizedBox(height: AppSpacing.m),
              Flexible(
                child: SingleChildScrollView(primary: false, child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
