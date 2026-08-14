/// 收藏句 FSRS 复习设置面板。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/bookmark_review_settings.dart';
import '../../providers/bookmark_review_settings_provider.dart';
import '../../theme/app_theme.dart';

/// 收藏复习设置面板。
///
/// 设置项直接监听全局 Provider，与其它学习任务设置弹窗保持一致，
/// 使每次更新都能立即反映到当前控件。
class BookmarkReviewSettingsSheet extends ConsumerWidget {
  const BookmarkReviewSettingsSheet({super.key});

  static const _minimumDailyReviewGoal = 5;
  static const _maximumDailyReviewGoal = 100;
  static const _dailyReviewGoalStep = 5;
  static const _dailyReviewGoalUnlimitedPosition =
      (_maximumDailyReviewGoal - _minimumDailyReviewGoal) /
          _dailyReviewGoalStep +
      1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(bookmarkReviewSettingsProvider);
    final notifier = ref.read(bookmarkReviewSettingsProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          AppSpacing.s,
          AppSpacing.l,
          AppSpacing.l,
        ),
        child: SingleChildScrollView(
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
              Text(
                l10n.bookmarkReviewSettingsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.bookmarkReviewShowNextReviewTime),
                value: settings.showNextReviewTime,
                onChanged: (value) => notifier.update(
                  settings.copyWith(showNextReviewTime: value),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.bookmarkReviewDailyGoal,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _dailyReviewGoalLabel(l10n, settings.dailyReviewGoal),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _dailyReviewGoalPosition(settings.dailyReviewGoal),
                min: 0,
                max: _dailyReviewGoalUnlimitedPosition,
                divisions: _dailyReviewGoalUnlimitedPosition.toInt(),
                label: _dailyReviewGoalLabel(l10n, settings.dailyReviewGoal),
                onChanged: (position) {
                  final goal = _dailyReviewGoalForPosition(position);
                  notifier.update(
                    goal == null
                        ? settings.copyWith(clearDailyReviewGoal: true)
                        : settings.copyWith(dailyReviewGoal: goal),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.l),
              Text(
                l10n.bookmarkReviewOrder,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              _BookmarkReviewOrderSelector(
                labels: {
                  BookmarkReviewOrder.smart: l10n.bookmarkReviewOrderSmart,
                  BookmarkReviewOrder.dueAt: l10n.bookmarkReviewOrderDueAt,
                  BookmarkReviewOrder.random: l10n.bookmarkReviewOrderRandom,
                },
                selected: settings.order,
                onSelected: (order) =>
                    notifier.update(settings.copyWith(order: order)),
              ),
              const SizedBox(height: AppSpacing.l),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.autoShowAiExplanationToggle),
                value: settings.autoShowAiExplanation,
                onChanged: (value) => notifier.update(
                  settings.copyWith(autoShowAiExplanation: value),
                ),
              ),
              if (settings.autoShowAiExplanation) ...[
                _AiExplanationSubSwitch(
                  title: l10n.autoShowAiAnalysisToggle,
                  value: settings.autoShowAiAnalysis,
                  onChanged: (value) => notifier.update(
                    settings.copyWith(autoShowAiAnalysis: value),
                  ),
                ),
                _AiExplanationSubSwitch(
                  title: l10n.autoShowAiTranslationToggle,
                  value: settings.autoShowAiTranslation,
                  onChanged: (value) => notifier.update(
                    settings.copyWith(autoShowAiTranslation: value),
                  ),
                ),
                _AiExplanationSubSwitch(
                  title: l10n.autoShowAiSenseGroupsToggle,
                  value: settings.autoShowAiSenseGroups,
                  onChanged: (value) => notifier.update(
                    settings.copyWith(autoShowAiSenseGroups: value),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 将每日目标映射为滑块位置，最右侧保留给“不限”。
  double _dailyReviewGoalPosition(int? goal) {
    if (goal == null) return _dailyReviewGoalUnlimitedPosition;
    return (goal - _minimumDailyReviewGoal) / _dailyReviewGoalStep;
  }

  /// 将离散滑块位置映射回持久化设置值。
  int? _dailyReviewGoalForPosition(double position) {
    final roundedPosition = position.round();
    if (roundedPosition == _dailyReviewGoalUnlimitedPosition) return null;
    return _minimumDailyReviewGoal + roundedPosition * _dailyReviewGoalStep;
  }

  String _dailyReviewGoalLabel(AppLocalizations l10n, int? goal) =>
      goal == null ? l10n.bookmarkReviewUnlimited : '$goal';
}

class _AiExplanationSubSwitch extends StatelessWidget {
  const _AiExplanationSubSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: const EdgeInsets.only(left: AppSpacing.l),
    title: Text(title),
    value: value,
    onChanged: onChanged,
  );
}

/// 复习顺序单选控件按当前本地化文案的实际宽度分配分段比例。
class _BookmarkReviewOrderSelector extends StatelessWidget {
  const _BookmarkReviewOrderSelector({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final Map<BookmarkReviewOrder, String> labels;
  final BookmarkReviewOrder selected;
  final ValueChanged<BookmarkReviewOrder> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final weights = _segmentWeights(
      context,
      labels.values.toList(growable: false),
      textStyle,
    );
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline;

    return Semantics(
      label: AppLocalizations.of(context)!.bookmarkReviewOrder,
      child: Stack(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                for (var index = 0; index < labels.length; index++)
                  Expanded(
                    flex: weights[index],
                    child: _BookmarkReviewOrderSegment(
                      key: Key(
                        'bookmark-review-order-${labels.keys.elementAt(index).name}',
                      ),
                      label: labels.values.elementAt(index),
                      isSelected: selected == labels.keys.elementAt(index),
                      textStyle: textStyle,
                      dividerColor: index == 0 ? null : borderColor,
                      selectedColor: colorScheme.secondaryContainer,
                      onTap: () => onSelected(labels.keys.elementAt(index)),
                    ),
                  ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 文本宽度加统一水平内边距，保证各段随文案和字体缩放变化。
  List<int> _segmentWeights(
    BuildContext context,
    List<String> labels,
    TextStyle? textStyle,
  ) => [
    for (final label in labels)
      ((TextPainter(
                text: TextSpan(text: label, style: textStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout()).width +
              48)
          .round(),
  ];
}

class _BookmarkReviewOrderSegment extends StatelessWidget {
  const _BookmarkReviewOrderSegment({
    super.key,
    required this.label,
    required this.isSelected,
    required this.textStyle,
    required this.dividerColor,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final TextStyle? textStyle;
  final Color? dividerColor;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? selectedColor : Colors.transparent,
        border: dividerColor == null
            ? null
            : Border(left: BorderSide(color: dividerColor!)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Center(child: Text(label, style: textStyle, softWrap: false)),
      ),
    ),
  );
}
