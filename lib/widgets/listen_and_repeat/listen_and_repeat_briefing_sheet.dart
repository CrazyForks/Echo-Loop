/// 跟读简报底部弹窗
///
/// 进入跟读前显示，告知用户难句数量、每句遍数和操作提示，
/// 同时让用户在弹窗里选择本次会话的初始播放速度（与盲听/复述对齐）。
library;

import 'package:flutter/material.dart';
import '../common/app_dropdown.dart';
import '../common/pause_choice_dropdown.dart';
import '../common/setting_labeled_row.dart';
import '../../l10n/app_localizations.dart';
import '../../models/intensive_listen_settings.dart';
import '../../models/stage_settings_overrides.dart' show BriefingPauseChoice;
import '../../theme/app_theme.dart';
import '../../utils/playback_speed.dart';
import '../common/briefing_action_row.dart';
import '../common/learning_briefing_sheet_content.dart';

/// 显示跟读简报底部弹窗
///
/// [defaultPlaybackSpeed] 默认播放速度（按难度+轮次映射），用户可在弹窗里改。
/// [defaultPause] 默认句间停顿(自动/固定间隔/句长倍数)，用于回显已记忆值。
/// [onStartPractice] 点击"开始练习"时回调，参数为用户最终选定的速度 + 句间停顿。
/// [onSkip] 可选，提供时在"开始练习"左侧显示「跳过」按钮，点击直接跳过当前任务。
Future<void> showListenAndRepeatBriefingSheet({
  required BuildContext context,
  required int difficultCount,
  required int playCount,
  Duration? estimatedDuration,
  double defaultPlaybackSpeed = 1.0,
  BriefingPauseChoice defaultPause = const BriefingPauseChoice.smart(),
  required void Function(double playbackSpeed, BriefingPauseChoice pause)
  onStartPractice,
  void Function(double playbackSpeed, BriefingPauseChoice pause)?
  onSelectionChanged,
  VoidCallback? onSkip,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => ListenAndRepeatBriefingSheet(
      difficultCount: difficultCount,
      playCount: playCount,
      estimatedDuration: estimatedDuration,
      defaultPlaybackSpeed: defaultPlaybackSpeed,
      defaultPause: defaultPause,
      onStartPractice: onStartPractice,
      onSelectionChanged: onSelectionChanged,
      onSkip: onSkip,
    ),
  );
}

class ListenAndRepeatBriefingSheet extends StatefulWidget {
  /// 难句总数
  final int difficultCount;

  /// 每句播放遍数
  final int playCount;

  /// 预估练习时长
  final Duration? estimatedDuration;

  /// 默认播放速度
  final double defaultPlaybackSpeed;

  /// 默认句间停顿(自动/固定间隔/句长倍数)。用于回显已记忆值。
  final BriefingPauseChoice defaultPause;

  /// 开始练习回调（带回最终选定的速度 + 句间停顿）
  final void Function(double playbackSpeed, BriefingPauseChoice pause)
  onStartPractice;

  /// 用户改动速度/停顿时即时回调(改完即记,与 🔧 面板一致,不必等「开始练习」)。
  final void Function(double playbackSpeed, BriefingPauseChoice pause)?
  onSelectionChanged;

  /// 跳过当前任务回调，提供时显示「跳过」按钮
  final VoidCallback? onSkip;

  const ListenAndRepeatBriefingSheet({
    super.key,
    required this.difficultCount,
    required this.playCount,
    this.estimatedDuration,
    this.defaultPlaybackSpeed = 1.0,
    this.defaultPause = const BriefingPauseChoice.smart(),
    required this.onStartPractice,
    this.onSelectionChanged,
    this.onSkip,
  });

  @override
  State<ListenAndRepeatBriefingSheet> createState() =>
      _ListenAndRepeatBriefingSheetState();
}

class _ListenAndRepeatBriefingSheetState
    extends State<ListenAndRepeatBriefingSheet> {
  late double _playbackSpeed = widget.defaultPlaybackSpeed;
  late BriefingPauseChoice _pause = widget.defaultPause;

  /// 格式化预估时长
  String _formatEstimatedDuration(AppLocalizations l10n, Duration duration) {
    final minutes = (duration.inSeconds / 60).ceil();
    if (minutes < 1) return l10n.estimatedLessThanOneMinute;
    return l10n.estimatedMinutes(minutes);
  }

  /// 统一显示速度标签：始终保留一位小数。
  String _formatSpeed(double speed) => formatPlaybackSpeedLabel(speed);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return LearningBriefingSheetContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // 图标
          Icon(
            Icons.record_voice_over,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.m),

          // 标题
          Text(
            l10n.listenAndRepeatBriefingTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // 练习提示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    l10n.listenAndRepeatBriefingTip,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),

          // 句间停顿（分组:自动 / 固定间隔 / 句长倍数,与 🔧 面板一致）
          SettingLabeledRow(
            label: Text(
              l10n.intensiveListenPauseLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: PauseChoiceDropdown(
              value: _pause,
              fixedOptions: IntensiveListenSettings.fixedPauseOptions,
              multiplierOptions: IntensiveListenSettings.multiplierOptions,
              onChanged: (v) {
                setState(() => _pause = v);
                widget.onSelectionChanged?.call(_playbackSpeed, v);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.m),

          // 播放速度（与盲听/复述对齐）
          SettingLabeledRow(
            label: Text(
              l10n.playbackSpeed,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: AppDropdown<double>(
              value: _playbackSpeed,
              isExpanded: true,
              isDense: true,
              items: IntensiveListenSettings.briefingPlaybackSpeedOptions
                  .map(
                    (speed) => DropdownMenuItem(
                      value: speed,
                      child: Text(_formatSpeed(speed)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _playbackSpeed = v);
                  widget.onSelectionChanged?.call(v, _pause);
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.m),

          // 难句数量 + 遍数 + 预估时长
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.listenAndRepeatBriefingDifficultCount(
                  widget.difficultCount,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                child: Text(
                  '·',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                l10n.listenAndRepeatBriefingPlayCount(widget.playCount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.estimatedDuration != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                  child: Text(
                    '·',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatEstimatedDuration(l10n, widget.estimatedDuration!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.l),

          // 开始练习按钮（+ 可选跳过）
          BriefingActionRow(
            startLabel: l10n.startPractice,
            onStart: () {
              Navigator.of(context).pop();
              widget.onStartPractice(_playbackSpeed, _pause);
            },
            skipLabel: widget.onSkip != null ? l10n.retellSkip : null,
            onSkip: widget.onSkip == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onSkip!();
                  },
          ),
        ],
      ),
    );
  }
}
