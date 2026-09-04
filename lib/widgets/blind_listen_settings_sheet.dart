/// 盲听设置面板
///
/// 底部弹窗，即时生效，仅本次会话。
/// 设置项：每段重复次数 + 停顿模式（固定间隔/段长倍数）
/// UI 风格与复述设置面板保持一致。
library;

import 'package:flutter/material.dart';
import 'common/app_dropdown.dart';
import 'common/setting_labeled_row.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/blind_listen_settings.dart';
import '../models/intensive_listen_settings.dart'
    show PauseMode, ShadowingControlMode;
import '../models/repeat_count_options.dart';
import '../providers/learning_session/blind_listen_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/playback_speed.dart';
import 'common/settings_sheet_scaffold.dart';

/// 显示盲听设置面板
Future<void> showBlindListenSettingsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => const _BlindListenSettingsSheet(),
  );
}

class _BlindListenSettingsSheet extends ConsumerWidget {
  const _BlindListenSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(blindListenPlayerProvider);
    final settings = state.settings;

    return SettingsSheetScaffold(
      title: l10n.blindListenSettingsTitle,
      subtitle: l10n.settingsSessionOnly,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 控制模式
          _buildControlModeSection(l10n, theme, settings, ref),
          const SizedBox(height: AppSpacing.l),

          // 重复次数和停顿设置仅在自动模式下显示
          if (!settings.isManualMode) ...[
            const SizedBox(height: AppSpacing.l),

            // 每段重复次数
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.retellRepeatCount,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                AppDropdown<int>(
                  value: settings.repeatCount,
                  items: [
                    ...kRepeatCountOptions.where((count) => count != 0).map((
                      count,
                    ) {
                      return DropdownMenuItem(
                        value: count,
                        child: Text('$count'),
                      );
                    }),
                    DropdownMenuItem(
                      value: 0,
                      child: Text(l10n.infiniteRepeat),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(blindListenPlayerProvider.notifier)
                          .updateSettings(
                            settings.copyWith(repeatCount: value),
                          );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),

            // 段间停顿标题
            Text(
              l10n.blindListenPauseBetween,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s),

            // 停顿模式切换
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PauseMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: PauseMode.smart,
                    label: Text(l10n.pauseModeSmart),
                  ),
                  ButtonSegment(
                    value: PauseMode.fixed,
                    label: Text(l10n.pauseModeFixed),
                  ),
                  ButtonSegment(
                    value: PauseMode.multiplier,
                    label: Text(l10n.pauseModeMultiplier),
                  ),
                ],
                selected: {settings.pauseMode},
                onSelectionChanged: (selected) {
                  ref
                      .read(blindListenPlayerProvider.notifier)
                      .updateSettings(
                        settings.copyWith(pauseMode: selected.first),
                      );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.m),

            // 停顿模式详情
            _buildPauseModeDetail(l10n, theme, settings, ref),
          ],

          const SizedBox(height: AppSpacing.l),

          // 播放速度放在控制相关设置之后，作为本次盲听的全局播放参数。
          _buildPlaybackSpeedSection(l10n, theme, settings, ref),
        ],
      ),
    );
  }

  /// 播放速度滑块。
  ///
  /// 盲听速度仅对当前会话生效，使用统一离散档位。
  Widget _buildPlaybackSpeedSection(
    AppLocalizations l10n,
    ThemeData theme,
    BlindListenSettings settings,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingLabeledRow(
          label: Text(
            l10n.playbackSpeed,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Text(
            _formatSpeed(settings.playbackSpeed),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Slider(
          value: playbackSpeedSliderValue(settings.playbackSpeed),
          min: 0,
          max: (kUnifiedPlaybackSpeeds.length - 1).toDouble(),
          divisions: kUnifiedPlaybackSpeeds.length - 1,
          label: _formatSpeed(settings.playbackSpeed),
          onChanged: (value) {
            final speed = playbackSpeedFromSliderValue(value);
            ref
                .read(blindListenPlayerProvider.notifier)
                .updateSettings(settings.copyWith(playbackSpeed: speed));
          },
        ),
      ],
    );
  }

  /// 控制模式选择区域
  Widget _buildControlModeSection(
    AppLocalizations l10n,
    ThemeData theme,
    BlindListenSettings settings,
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
              ref
                  .read(blindListenPlayerProvider.notifier)
                  .updateSettings(
                    settings.copyWith(controlMode: selected.first),
                  );
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
                    ? l10n.blindListenControlModeManualDesc
                    : l10n.blindListenControlModeAutoDesc,
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

  /// 停顿模式详情区域
  Widget _buildPauseModeDetail(
    AppLocalizations l10n,
    ThemeData theme,
    BlindListenSettings settings,
    WidgetRef ref,
  ) {
    return switch (settings.pauseMode) {
      PauseMode.smart => Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              l10n.listenAndRepeatPauseSmartDesc,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
      PauseMode.multiplier => _buildChipGrid(
        items: BlindListenSettings.multiplierOptions,
        labelBuilder: (v) => v == v.roundToDouble() ? '${v.toInt()}x' : '${v}x',
        selected: (v) => settings.pauseMultiplier == v,
        onSelected: (v) => ref
            .read(blindListenPlayerProvider.notifier)
            .updateSettings(settings.copyWith(pauseMultiplier: v)),
      ),
      PauseMode.fixed => () {
        final options = BlindListenSettings.fixedPauseOptions;
        var idx = options.indexOf(settings.fixedPauseSeconds);
        if (idx < 0) idx = 1; // 回退到 10s（默认值）
        return Row(
          children: [
            Expanded(
              child: Slider(
                value: idx.toDouble(),
                min: 0,
                max: (options.length - 1).toDouble(),
                divisions: options.length - 1,
                label: '${options[idx]}s',
                onChanged: (v) {
                  ref
                      .read(blindListenPlayerProvider.notifier)
                      .updateSettings(
                        settings.copyWith(
                          fixedPauseSeconds: options[v.round()],
                        ),
                      );
                },
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${settings.fixedPauseSeconds}s',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      }(),
    };
  }

  /// 等宽网格排列 ChoiceChip，每行 4 个
  Widget _buildChipGrid<T>({
    required List<T> items,
    required String Function(T) labelBuilder,
    required bool Function(T) selected,
    required void Function(T) onSelected,
  }) {
    const columns = 4;
    final rows = (items.length / columns).ceil();

    return Column(
      children: List.generate(rows, (row) {
        final start = row * columns;
        final end = (start + columns).clamp(0, items.length);
        final rowItems = items.sublist(start, end);

        return Padding(
          padding: EdgeInsets.only(top: row > 0 ? AppSpacing.xs : 0),
          child: Row(
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: i < rowItems.length
                      ? ChoiceChip(
                          showCheckmark: false,
                          label: SizedBox(
                            width: double.infinity,
                            child: Text(
                              labelBuilder(rowItems[i]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          selected: selected(rowItems[i]),
                          onSelected: (s) {
                            if (s) onSelected(rowItems[i]);
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  /// 统一显示速度标签：始终保留一位小数。
  String _formatSpeed(double speed) => formatPlaybackSpeedLabel(speed);
}
