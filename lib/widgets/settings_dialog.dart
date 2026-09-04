/// 自由练习（全能播放器）循环设置浮层
///
/// 悬浮在控制栏循环图标上方的浮层（非底部 sheet），即时生效并持久化。包含两组
/// **相互独立、可同时开启**的循环：
/// - 整篇循环：整篇播完后回到开头重播，可设总遍数（含 ∞）与每遍间隔。
/// - 单句循环：每句重复若干次（含 ∞）后进下一句，可设次数与每次间隔。
///
/// 每个区块由一个主开关控制；开启后用 [AnimatedSize] 展开「重复次数 / 间隔时长」两行
/// 滑块。布局紧凑：标签、滑条、当前值同处一行。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/playback_settings.dart';
import '../models/repeat_count_options.dart';
import '../providers/listening_practice/listening_practice_provider.dart';
import '../theme/app_theme.dart';

/// 循环设置浮层内容（气泡卡片内部内容）。
///
/// 由调用方用 [AnchoredBubble] 锚定到循环按钮上方并套上气泡卡片外壳，本组件只负责
/// 卡片内的两组循环设置（整篇 / 单句）。
class LoopSettingsPopup extends ConsumerWidget {
  const LoopSettingsPopup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      listeningPracticeProvider.select((s) => s.settings),
    );
    // 单句循环依赖字幕分句，无字幕时只保留整篇循环。
    final hasSentences = ref.watch(
      listeningPracticeProvider.select((s) => s.hasSentences),
    );
    final controller = ref.read(listeningPracticeProvider.notifier);

    return LoopSettingsContent(
      settings: settings,
      hasSentences: hasSentences,
      onChanged: controller.updateSettings,
    );
  }
}

/// 可由不同播放控制器复用的循环设置内容。
///
/// 组件只负责整篇/单句循环的展示与交互，状态来源和持久化由调用方通过 [onChanged]
/// 注入，确保音频与媒体随心听共用同一套次数、间隔和布局规则。
class LoopSettingsContent extends StatelessWidget {
  const LoopSettingsContent({
    super.key,
    required this.settings,
    required this.hasSentences,
    required this.onChanged,
  });

  final PlaybackSettings settings;
  final bool hasSentences;
  final ValueChanged<PlaybackSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 整篇循环
          _LoopSection(
            icon: Icons.repeat,
            title: l10n.wholeTextLoop,
            enabled: settings.loopWhole,
            count: settings.wholeLoopCount,
            intervalSeconds: settings.wholeInterval.inSeconds,
            onEnabledChanged: (v) => onChanged(settings.copyWith(loopWhole: v)),
            onCountChanged: (v) =>
                onChanged(settings.copyWith(wholeLoopCount: v)),
            onIntervalChanged: (v) => onChanged(
              settings.copyWith(wholeInterval: Duration(seconds: v)),
            ),
          ),
          // 单句循环（无字幕时隐藏，连同分隔线）
          if (hasSentences) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            _LoopSection(
              icon: Icons.repeat_one,
              title: l10n.singleSentenceLoop,
              enabled: settings.loopSentence,
              count: settings.sentenceLoopCount,
              intervalSeconds: settings.sentenceInterval.inSeconds,
              onEnabledChanged: (v) =>
                  onChanged(settings.copyWith(loopSentence: v)),
              onCountChanged: (v) =>
                  onChanged(settings.copyWith(sentenceLoopCount: v)),
              onIntervalChanged: (v) => onChanged(
                settings.copyWith(sentenceInterval: Duration(seconds: v)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单组循环区块：紧凑主开关行 + 开启后展开的两行「标签 + 滑条 + 值」。
class _LoopSection extends StatelessWidget {
  const _LoopSection({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.count,
    required this.intervalSeconds,
    required this.onEnabledChanged,
    required this.onCountChanged,
    required this.onIntervalChanged,
  });

  /// 区块图标（整篇=repeat，单句=repeat_one）。
  final IconData icon;

  /// 区块标题。
  final String title;

  /// 该循环是否开启。
  final bool enabled;

  /// 重复次数模型值：`0`=∞，`1-10/20/30/40/50`=有限。
  final int count;

  /// 间隔秒数（0-10）。
  final int intervalSeconds;

  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onCountChanged;
  final ValueChanged<int> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // 图标 / 标题随开关状态变色：开启高亮 primary，关闭弱化 onSurfaceVariant
    final accent = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 紧凑主开关行：整行可点切换开关
        InkWell(
          onTap: () => onEnabledChanged(!enabled),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Icon(icon, size: 20, color: accent),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: onEnabledChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
        // 子设置：开启后展开
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: enabled
              ? Column(
                  children: [
                    // 重复次数：1-10、20、30、40、50 + ∞（末位）
                    _LabeledSliderRow(
                      label: l10n.repeatCount,
                      sliderValue: _countToSlider(count),
                      min: 0,
                      max: (kRepeatCountOptions.length - 1).toDouble(),
                      divisions: kRepeatCountOptions.length - 1,
                      valueLabel: _countLabel(l10n, count),
                      onChanged: (pos) => onCountChanged(_sliderToCount(pos)),
                    ),
                    // 间隔时长：0-10 秒（值列带「秒」单位）
                    _LabeledSliderRow(
                      label: l10n.intervalTime,
                      sliderValue: intervalSeconds.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      valueLabel: l10n.loopIntervalValue(intervalSeconds),
                      onChanged: (v) => onIntervalChanged(v.round()),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// 次数模型值 → 滑块位置；∞(0) 位于选项列表最右端。
  static double _countToSlider(int count) {
    final index = kRepeatCountOptions.indexOf(count);
    return (index < 0 ? 0 : index).toDouble();
  }

  /// 滑块位置 → 次数模型值。
  static int _sliderToCount(double pos) {
    final index = pos.round().clamp(0, kRepeatCountOptions.length - 1);
    return kRepeatCountOptions[index];
  }

  /// 次数显示文案：∞ 或本地化「N 次 / Nx」。
  static String _countLabel(AppLocalizations l10n, int count) =>
      count == 0 ? '∞' : l10n.loopCountValue(count);
}

/// 紧凑的「标签 + 滑条 + 当前值」单行组件。
class _LabeledSliderRow extends StatelessWidget {
  const _LabeledSliderRow({
    required this.label,
    required this.sliderValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double sliderValue;
  final double min;
  final double max;
  final int divisions;

  /// 右侧及拖动气泡显示的当前值文案。
  final String valueLabel;

  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: sliderValue.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
              semanticFormatterCallback: (_) => valueLabel,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
