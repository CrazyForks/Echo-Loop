/// 难句补练/收藏复习设置底部弹窗
///
/// 支持配置盲听循环次数、跟读循环次数和句间停顿模式。
/// 所有修改即时生效，设置仅对当次练习有效。
/// 提供两个入口函数分别对应难句补练和收藏复习 Provider。
library;

import 'package:flutter/material.dart';
import '../common/app_dropdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/difficult_practice_settings.dart';
import '../../models/intensive_listen_settings.dart';
import '../../providers/learning_session/review_difficult_practice_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_speed.dart';
import '../common/settings_sheet_scaffold.dart';

/// 显示难句补练设置底部弹窗
void showDifficultPracticeSettingsSheet({required BuildContext context}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _DifficultPracticeSettingsSheet(
      settingsSelector: (ref) =>
          ref.watch(reviewDifficultPracticeProvider.select((s) => s.settings)),
      onUpdate: (ref, settings) => ref
          .read(reviewDifficultPracticeProvider.notifier)
          .updateSettings(settings),
    ),
  );
}

/// 设置面板（即时生效，无需确认按钮）
///
/// 通过 [settingsSelector] 和 [onUpdate] 回调实现多 Provider 复用。
class _DifficultPracticeSettingsSheet extends ConsumerWidget {
  final DifficultPracticeSettings Function(WidgetRef ref) settingsSelector;
  final void Function(WidgetRef ref, DifficultPracticeSettings settings)
  onUpdate;

  const _DifficultPracticeSettingsSheet({
    required this.settingsSelector,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = settingsSelector(ref);

    return SettingsSheetScaffold(
      title: l10n.difficultPracticeSettings,
      subtitle: l10n.difficultPracticeSettingsHint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 控制模式
          _buildControlModeSection(l10n, theme, settings, ref),
          const SizedBox(height: AppSpacing.l),

          // 播放速度（手动/自动都生效）
          _buildPlaybackSpeedSection(l10n, theme, settings, ref),

          // 自动模式才显示循环次数和停顿设置
          if (!settings.isManualMode) ...[
            const SizedBox(height: AppSpacing.l),

            // 盲听循环次数
            _buildRepeatRow(
              label: l10n.difficultPracticeBlindListenRepeat,
              value: settings.blindListenRepeatCount,
              l10n: l10n,
              theme: theme,
              onChanged: (value) => onUpdate(
                ref,
                settings.copyWith(blindListenRepeatCount: value),
              ),
            ),
            const SizedBox(height: AppSpacing.m),

            // 跟读循环次数
            _buildRepeatRow(
              label: l10n.difficultPracticeShadowReadingRepeat,
              value: settings.shadowReadingRepeatCount,
              l10n: l10n,
              theme: theme,
              onChanged: (value) => onUpdate(
                ref,
                settings.copyWith(shadowReadingRepeatCount: value),
              ),
            ),
            const SizedBox(height: AppSpacing.l),

            // 句间停顿
            Text(
              l10n.intensiveListenPauseLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s),

            // 模式切换
            _buildPauseModeSelector(l10n, settings, ref),
            const SizedBox(height: AppSpacing.m),

            // 模式详情
            _buildPauseModeDetail(l10n, theme, settings, ref),
          ],
        ],
      ),
    );
  }

  /// 播放速度滑块
  ///
  /// 速度仅对当前会话生效，使用统一离散档位。
  Widget _buildPlaybackSpeedSection(
    AppLocalizations l10n,
    ThemeData theme,
    DifficultPracticeSettings settings,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.playbackSpeed,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _formatSpeed(settings.playbackSpeed),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: playbackSpeedSliderValue(settings.playbackSpeed),
          min: 0,
          max: (kUnifiedPlaybackSpeeds.length - 1).toDouble(),
          divisions: kUnifiedPlaybackSpeeds.length - 1,
          label: _formatSpeed(settings.playbackSpeed),
          onChanged: (value) {
            final speed = playbackSpeedFromSliderValue(value);
            onUpdate(ref, settings.copyWith(playbackSpeed: speed));
          },
        ),
      ],
    );
  }

  /// 统一显示速度标签：始终保留一位小数。
  String _formatSpeed(double speed) => formatPlaybackSpeedLabel(speed);

  /// 控制模式选择区域（自动/手动）
  Widget _buildControlModeSection(
    AppLocalizations l10n,
    ThemeData theme,
    DifficultPracticeSettings settings,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.listenAndRepeatControlModeLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ShadowingControlMode>(
            segments: [
              ButtonSegment(
                value: ShadowingControlMode.auto,
                label: Text(l10n.listenAndRepeatControlModeAuto),
                icon: const Icon(Icons.autorenew, size: 18),
              ),
              ButtonSegment(
                value: ShadowingControlMode.manual,
                label: Text(l10n.listenAndRepeatControlModeManual),
                icon: const Icon(Icons.touch_app, size: 18),
              ),
            ],
            selected: {settings.controlMode},
            onSelectionChanged: (selected) {
              onUpdate(ref, settings.copyWith(controlMode: selected.first));
            },
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                settings.isManualMode
                    ? l10n.listenAndRepeatControlModeManualDesc
                    : l10n.listenAndRepeatControlModeAutoDesc,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 循环次数选择行
  Widget _buildRepeatRow({
    required String label,
    required int value,
    required AppLocalizations l10n,
    required ThemeData theme,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        const SizedBox(width: AppSpacing.s),
        AppDropdown<int>(
          value: value,
          items: [
            ...List.generate(10, (i) => i + 1).map((count) {
              return DropdownMenuItem(
                value: count,
                child: Text(l10n.intensiveListenRepeatCountValue(count)),
              );
            }),
            DropdownMenuItem(value: 0, child: Text(l10n.infiniteRepeat)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  /// 停顿模式切换（SegmentedButton）
  Widget _buildPauseModeSelector(
    AppLocalizations l10n,
    DifficultPracticeSettings settings,
    WidgetRef ref,
  ) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<PauseMode>(
        segments: [
          ButtonSegment(
            value: PauseMode.smart,
            label: Text(l10n.intensiveListenPauseSmart),
          ),
          ButtonSegment(
            value: PauseMode.fixed,
            label: Text(l10n.intensiveListenPauseFixed),
          ),
          ButtonSegment(
            value: PauseMode.multiplier,
            label: Text(l10n.intensiveListenPauseMultiplierMode),
          ),
        ],
        selected: {settings.pauseMode},
        onSelectionChanged: (selected) {
          onUpdate(ref, settings.copyWith(pauseMode: selected.first));
        },
        showSelectedIcon: false,
      ),
    );
  }

  /// 停顿模式详情区域
  Widget _buildPauseModeDetail(
    AppLocalizations l10n,
    ThemeData theme,
    DifficultPracticeSettings settings,
    WidgetRef ref,
  ) {
    switch (settings.pauseMode) {
      case PauseMode.smart:
        return Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                l10n.intensiveListenPauseSmartDesc,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ),
          ],
        );

      case PauseMode.fixed:
        final options = IntensiveListenSettings.fixedPauseOptions;
        final seconds = settings.fixedPauseSeconds;
        // 将当前值映射到选项索引，保证 divisions 数量少、刻度点清晰可见
        var idx = options.indexOf(seconds);
        if (idx < 0) idx = 2; // 回退到 3 秒
        return Row(
          children: [
            Expanded(
              child: Slider(
                value: idx.toDouble(),
                min: 0,
                max: (options.length - 1).toDouble(),
                divisions: options.length - 1,
                label: '${options[idx]}s',
                onChanged: (v) => onUpdate(
                  ref,
                  settings.copyWith(fixedPauseSeconds: options[v.round()]),
                ),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${seconds}s',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );

      case PauseMode.multiplier:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.intensiveListenPauseMultiplierLabel,
              style: theme.textTheme.bodyLarge,
            ),
            AppDropdown<double>(
              value: settings.pauseMultiplier,
              items: IntensiveListenSettings.multiplierOptions.map((value) {
                return DropdownMenuItem(
                  value: value,
                  child: Text(
                    l10n.intensiveListenPauseMultiplierValue(
                      value.toStringAsFixed(
                        value == value.roundToDouble() ? 0 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  onUpdate(ref, settings.copyWith(pauseMultiplier: value));
                }
              },
            ),
          ],
        );
    }
  }
}
