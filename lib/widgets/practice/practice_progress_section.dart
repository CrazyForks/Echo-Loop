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

/// 练习页顶部的按句进度条。
///
/// 只负责进度展示与跳句操作。句次、时间和收藏等元信息由
/// [PracticeSentenceInfoRow] 独立呈现，宿主按页面需要组合两者。
class PracticeProgressBar extends StatelessWidget {
  /// 当前句子序号（1-based）
  final int current;

  /// 句子总数
  final int total;

  /// 拖动跳转回调（0-based 句索引，保证落在 `[0, total)`）。
  ///
  /// 非 null 且 [total] > 1 时进度条变为可拖动滑块；为 null 时保持只读进度条。
  final void Function(int targetIndex)? onSeek;

  /// 当前句在整篇音频时间轴上的已播放时长。
  final Duration? elapsed;

  /// 当前句之后到整篇音频结尾的剩余时长。
  final Duration? remaining;

  const PracticeProgressBar({
    super.key,
    required this.current,
    required this.total,
    this.onSeek,
    this.elapsed,
    this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final seek = onSeek;
    return Padding(
      // 保留讲解区上方的呼吸空间，与拆分前的进度区垂直留白一致。
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        0,
      ),
      child: _ProgressBarWithDurations(
        elapsed: elapsed,
        remaining: remaining,
        child: seek != null && total > 1
            ? _SeekableProgressBar(
                current: current.clamp(1, total),
                total: total,
                onSeek: seek,
              )
            : _StaticProgressBar(
                value: total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0,
              ),
      ),
    );
  }
}

/// 将整篇音频时长与句子进度条保持在同一行。
class _ProgressBarWithDurations extends StatelessWidget {
  const _ProgressBarWithDurations({
    required this.elapsed,
    required this.remaining,
    required this.child,
  });

  final Duration? elapsed;
  final Duration? remaining;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (elapsed == null || remaining == null) return child;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
    );
    return Row(
      children: [
        Text(_formatDuration(elapsed!), style: style),
        const SizedBox(width: AppSpacing.s),
        Expanded(child: child),
        const SizedBox(width: AppSpacing.s),
        Text('-${_formatDuration(remaining!)}', style: style),
      ],
    );
  }
}

/// 格式化播放时长，长音频才显示小时，保持进度条单行紧凑。
String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 固定高度的只读进度条，确保已播放和未播放轨道视觉上等粗。
class _StaticProgressBar extends StatelessWidget {
  const _StaticProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('practice-static-progress-bar'),
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1.5),
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value,
              heightFactor: 1,
              child: ColoredBox(color: colors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// 练习页顶部的句子元信息行。
///
/// 与 [PracticeProgressBar] 使用相同水平边距，保证组合使用时视觉对齐。
class PracticeSentenceInfoRow extends StatelessWidget {
  const PracticeSentenceInfoRow({
    super.key,
    required this.progressText,
    this.durationText,
    this.timestampText,
    this.audioName,
    this.showAudioSource = false,
    this.l10n,
    this.trailing,
  });

  final String progressText;
  final String? durationText;
  final String? timestampText;
  final String? audioName;
  final bool showAudioSource;
  final AppLocalizations? l10n;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final timestampStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.xs,
        AppSpacing.m,
        AppSpacing.s,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        progressText,
                        style: subtitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (durationText case final dur?) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text('·', style: subtitleStyle),
                      const SizedBox(width: AppSpacing.xs),
                      Text(dur, style: subtitleStyle),
                    ],
                    if (timestampText case final ts?) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          ts,
                          style: timestampStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing case final action?) action,
            ],
          ),
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
/// 避免拖动中反复触发跳转、重启音频流。视觉上通过 [SliderTheme] 保持
/// 等高的细轨道和小滑块，贴近原 [LinearProgressIndicator] 的高度。
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
        // 轨道高度由自定义 shape 保持两段一致，避免 Material 3 默认把
        // active track 额外加粗 2px。
        trackHeight: 2,
        trackShape: const _EqualHeightRoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: theme.colorScheme.primary,
        inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
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

/// 让 Material 滑块的已播放与未播放轨道使用完全相同高度的轨道形状。
///
/// Flutter 默认的 [RoundedRectSliderTrackShape] 会为 active track 增加 2px
/// 高度，导致同一进度条的两段视觉粗细不一致。
class _EqualHeightRoundedRectSliderTrackShape
    extends RoundedRectSliderTrackShape {
  const _EqualHeightRoundedRectSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: 0,
    );
  }
}
