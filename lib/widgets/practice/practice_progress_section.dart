/// 练习页面共享的顶部进度条区域
///
/// 显示线性进度条、句数进度、句子时长、时间戳。
/// 当 [showAudioSource] 为 true 且 [audioName] 非 null 时额外显示音频来源行。
/// 用于难句补练、难句跟读和收藏复习。
///
/// 当传入 [onSeek] 且总句数大于 1 时，进度条变为按句吸附的可拖动滑块：
/// 用户拖动时滑块跟手，松手后回调目标句的 0-based 索引；否则保持只读进度条。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// 顶部进度条区域
class PracticeProgressSection extends StatelessWidget {
  /// 当前句子序号（1-based）
  final int current;

  /// 句子总数
  final int total;

  /// 进度文本（如 "第 4/55 句"），由调用方通过 l10n 生成
  final String progressText;

  /// 句子时长文本（如 "2.3s"）
  final String? durationText;

  /// 音频来源名称（非 null 时显示来源行）
  final String? audioName;

  /// 是否显示音频来源行
  final bool showAudioSource;

  /// 时间戳文本（如 "01:23.4 - 01:25.7"）
  final String? timestampText;

  /// 本地化（仅 audioName 非 null 时用于来源行文案）
  final AppLocalizations? l10n;

  /// 拖动跳转回调（0-based 句索引，保证落在 `[0, total)`）。
  ///
  /// 非 null 且 [total] > 1 时进度条变为可拖动滑块；为 null 时保持只读进度条。
  final void Function(int targetIndex)? onSeek;

  /// 进度信息行右侧的可选操作（例如收藏/难句按钮）。
  final Widget? trailing;

  const PracticeProgressSection({
    super.key,
    required this.current,
    required this.total,
    required this.progressText,
    this.durationText,
    this.audioName,
    this.showAudioSource = false,
    this.timestampText,
    this.l10n,
    this.onSeek,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = total > 0 ? current / total : 0.0;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final timestampStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      child: Column(
        children: [
          if (onSeek case final seek? when total > 1)
            _SeekableProgressBar(
              current: current.clamp(1, total),
              total: total,
              onSeek: seek,
            )
          else
            LinearProgressIndicator(
              value: progress,
              borderRadius: BorderRadius.circular(2),
            ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(progressText, style: subtitleStyle),
              if (durationText case final dur?) ...[
                const SizedBox(width: AppSpacing.xs),
                Text('·', style: subtitleStyle),
                const SizedBox(width: AppSpacing.xs),
                Text(dur, style: subtitleStyle),
              ],
              if (timestampText case final ts?) ...[
                const SizedBox(width: 6),
                Text(ts, style: timestampStyle),
              ],
              const Spacer(),
              // 右侧操作按自身宽度布局，只让 Spacer 消化剩余空间。
              // 若再用 Flexible，它会与 Spacer 平分剩余宽度，使按钮停在页面中部。
              if (trailing case final action?) action,
            ],
          ),
          // 来源音频名称
          if (showAudioSource && audioName != null && l10n != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.audiotrack,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n!.bookmarkReviewFromAudio(audioName!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 按句吸附的可拖动进度滑块
///
/// 用 [Slider] 按句分档（divisions = total - 1）。拖动过程中只更新本地
/// [_dragValue] 让滑块跟手，松手（onChangeEnd）时才回调目标句索引，
/// 避免拖动中反复触发跳转、重启音频流。视觉上通过 [SliderTheme] 收紧为
/// 细轨道小滑块，贴近原 [LinearProgressIndicator] 的高度。
class _SeekableProgressBar extends StatefulWidget {
  /// 当前句子序号（1-based，已 clamp 到 `[1, total]`）
  final int current;

  /// 句子总数（调用方保证 > 1）
  final int total;

  /// 松手时的跳转回调（0-based 句索引）
  final void Function(int targetIndex) onSeek;

  const _SeekableProgressBar({
    required this.current,
    required this.total,
    required this.onSeek,
  });

  @override
  State<_SeekableProgressBar> createState() => _SeekableProgressBarState();
}

class _SeekableProgressBarState extends State<_SeekableProgressBar> {
  /// 拖动中的临时值（1-based）；非拖动时为 null，滑块跟随 [widget.current]
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (_dragValue ?? widget.current.toDouble()).clamp(
      1.0,
      widget.total.toDouble(),
    );

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: theme.colorScheme.primary,
        inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.2),
        thumbColor: theme.colorScheme.primary,
      ),
      child: Slider(
        min: 1,
        max: widget.total.toDouble(),
        divisions: widget.total - 1,
        value: value,
        label: '${value.round()}',
        padding: EdgeInsets.zero,
        onChanged: (v) => setState(() => _dragValue = v),
        onChangeEnd: (v) {
          setState(() => _dragValue = null);
          widget.onSeek(v.round() - 1);
        },
      ),
    );
  }
}
