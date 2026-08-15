/// 步骤完成通用对话框
///
/// 合并了精听、跟读、复述、难句补练、盲听等多个播放器页面的完成对话框。
/// 统一的「成就卡」布局，自上而下：
/// 1. 顶部英雄区（hero header）：柔和色带背景 + 圆形勾选徽章（入场缩放）+
///    居中标题 + 居中步骤进度
/// 2. 统计行（可选）：把关键数字抽成高亮 chip，数字大、品牌蓝
/// 3. 自定义鼓励语（可选，居中）
/// 4. 底部操作按钮
///
/// 按钮布局根据上下文分三种情况：
/// 1. 有下一步可继续：[完成] [继续]
/// 2. 末步骤：[完成首次学习/复习]（全宽）
/// 3. 非末步骤但下一步不可用：[完成]（全宽）
///
/// 使用 [showDialog] + `useRootNavigator: true` 显示弹窗，
/// 弹窗挂到 root Navigator，与 GoRouter 路由栈隔离。
/// `barrierDismissible: true`，点击外部区域或右上角关闭按钮返回 null。
library;

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'completion_dialog_parts.dart';

/// 用户在完成对话框中的选择
enum StepCompleteAction {
  /// 继续下一步
  continueNext,

  /// 完成当前步骤，返回计划页
  back,
}

/// 步骤完成对话框返回结果
///
/// [action] 用户选择的操作。
typedef StepCompleteResult = ({StepCompleteAction action});

/// 单条完成统计项（复用 [CompletionStat]）
typedef StepCompleteStat = CompletionStat;

/// 显示步骤完成对话框
///
/// 返回 `null` 表示用户点击外部区域或关闭按钮关闭，
/// 返回 [StepCompleteResult] 表示用户点击了操作按钮。
///
/// [title] 对话框标题文本。
/// [stats] 高亮统计项（可选）；非空时渲染为统计 chip 行。
/// [contentBody] 自定义内容区域（如鼓励语），居中显示。
/// [stepIndex] 当前完成的步骤序号（0-based），null 表示不显示步骤进度。
/// [totalSteps] 当前阶段总步骤数。
/// [stageName] 当前阶段名称（如"首次学习"）。
/// [nextStepName] 下一步名称（null 表示下一步不可用或不存在）。
/// [isLastStep] 是否为当前阶段的最后一步。
Future<StepCompleteResult?> showStepCompleteDialog({
  required BuildContext context,
  required String title,
  List<StepCompleteStat>? stats,
  Widget? contentBody,
  int? stepIndex,
  int? totalSteps,
  String? stageName,
  String? nextStepName,
  bool isLastStep = false,
}) {
  return showDialog<StepCompleteResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (dialogContext) => StepCompleteDialog(
      onResult: (result) => Navigator.of(dialogContext).pop(result),
      title: title,
      stats: stats,
      contentBody: contentBody,
      stepIndex: stepIndex,
      totalSteps: totalSteps,
      stageName: stageName,
      nextStepName: nextStepName,
      isLastStep: isLastStep,
    ),
  );
}

/// 步骤完成通用对话框组件
class StepCompleteDialog extends StatefulWidget {
  /// 对话框标题
  final String title;

  /// 高亮统计项（null = 不显示统计行）
  final List<StepCompleteStat>? stats;

  /// 自定义内容区域
  final Widget? contentBody;

  /// 当前步骤序号（0-based），null 则不显示步骤进度
  final int? stepIndex;

  /// 总步骤数
  final int? totalSteps;

  /// 阶段名称
  final String? stageName;

  /// 下一步名称（null = 不可用）
  final String? nextStepName;

  /// 是否为最后一步
  final bool isLastStep;

  /// 结果回调
  final void Function(StepCompleteResult?) onResult;

  const StepCompleteDialog({
    super.key,
    required this.onResult,
    required this.title,
    this.stats,
    this.contentBody,
    this.stepIndex,
    this.totalSteps,
    this.stageName,
    this.nextStepName,
    this.isLastStep = false,
  });

  @override
  State<StepCompleteDialog> createState() => _StepCompleteDialogState();
}

class _StepCompleteDialogState extends State<StepCompleteDialog> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部英雄区（徽章 + 标题 + 步骤进度）
              CompletionHeroHeader(
                title: widget.title,
                subtitle: _progressSubtitle(l10n),
              ),
              // 主体内容（统计 + 鼓励语 + 按钮）
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.m,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 统计行
                    if (widget.stats != null && widget.stats!.isNotEmpty) ...[
                      CompletionStatsRow(stats: widget.stats!),
                      const SizedBox(height: AppSpacing.m),
                    ],
                    // 自定义内容（居中鼓励语）
                    if (widget.contentBody != null) ...[
                      DefaultTextStyle.merge(
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        child: widget.contentBody!,
                      ),
                      const SizedBox(height: AppSpacing.l),
                    ],
                    // 底部操作按钮
                    ..._buildActions(context, l10n),
                  ],
                ),
              ),
            ],
          ),
          // 右上角关闭按钮（落在绿色色带上，用中性灰保证对比度且不抢眼）
          Positioned(
            right: AppSpacing.xs,
            top: AppSpacing.xs,
            child: IconButton(
              onPressed: () => widget.onResult(null),
              icon: const Icon(Icons.close, size: 20),
              color: cs.onSurfaceVariant,
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 步骤进度副标题文案（信息不全时返回 null）
  String? _progressSubtitle(AppLocalizations l10n) {
    if (widget.stepIndex == null ||
        widget.totalSteps == null ||
        widget.stageName == null) {
      return null;
    }
    return l10n.stepProgressLabel(
      widget.stepIndex! + 1,
      widget.totalSteps!,
      widget.stageName!,
    );
  }

  /// 构建底部操作按钮
  ///
  /// 三种情况：
  /// 1. 有下一步可继续：[完成 Outlined] [继续 Filled] 同一行
  /// 2. 末步骤：[完成首次学习/复习 Filled]（全宽）
  /// 3. 非末步骤但下一步不可用：[完成 Filled]（全宽）
  List<Widget> _buildActions(BuildContext context, AppLocalizations l10n) {
    if (widget.nextStepName != null) {
      // 情况 1：有下一步可继续
      return [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: () =>
                    widget.onResult((action: StepCompleteAction.back)),
                child: Text(l10n.done),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              flex: 3,
              child: FilledButton(
                onPressed: () =>
                    widget.onResult((action: StepCompleteAction.continueNext)),
                child: Text(l10n.continueButton),
              ),
            ),
          ],
        ),
      ];
    } else if (widget.isLastStep) {
      // 情况 2：末步骤
      final l10nCtx = AppLocalizations.of(context)!;
      final isFirstStudy = widget.stageName == l10nCtx.firstStudy;
      final completeText = isFirstStudy
          ? l10n.completeFirstStudy
          : l10n.completeReview;

      return [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => widget.onResult((action: StepCompleteAction.back)),
            child: Text(completeText),
          ),
        ),
      ];
    } else {
      // 情况 3：非末步骤但下一步不可用
      return [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => widget.onResult((action: StepCompleteAction.back)),
            child: Text(l10n.done),
          ),
        ),
      ];
    }
  }
}
