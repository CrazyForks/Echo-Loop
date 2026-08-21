/// 收藏复习共用设置面板。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/favorite_review_settings.dart';
import '../../providers/bookmark_review_settings_provider.dart';
import '../../providers/favorite_review_settings_provider.dart';
import '../../theme/app_theme.dart';
import '../common/settings_section_card.dart';

enum FavoriteReviewSettingsTask { sentence, vocabulary, favorites }

/// 收藏复习设置面板。
///
/// 设置项直接监听全局 Provider，与其它学习任务设置弹窗保持一致，
/// 使每次更新都能立即反映到当前控件。
class BookmarkReviewSettingsSheet extends ConsumerStatefulWidget {
  const BookmarkReviewSettingsSheet({super.key, required this.task});

  final FavoriteReviewSettingsTask task;

  @override
  ConsumerState<BookmarkReviewSettingsSheet> createState() =>
      _BookmarkReviewSettingsSheetState();
}

class _BookmarkReviewSettingsSheetState
    extends ConsumerState<BookmarkReviewSettingsSheet> {
  /// 折叠区展开态本地跟踪，仅用于控制标题栏置灰，不涉及业务状态。
  late bool _sentenceExpanded =
      widget.task == FavoriteReviewSettingsTask.sentence;
  late bool _vocabularyExpanded =
      widget.task == FavoriteReviewSettingsTask.vocabulary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(favoriteReviewSettingsProvider);
    final notifier = ref.read(favoriteReviewSettingsProvider.notifier);
    final sentenceSettings = ref.watch(bookmarkReviewSettingsProvider);
    final sentenceNotifier = ref.read(bookmarkReviewSettingsProvider.notifier);
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
              const SizedBox(height: AppSpacing.m),
              SettingsSectionCard(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.bookmarkReviewShowNextReviewTime),
                    value: settings.showNextReviewTime,
                    onChanged: (value) => notifier.update(
                      settings.copyWith(showNextReviewTime: value),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.favoriteReviewAutoPlayFront),
                    value: settings.autoPlayFront,
                    onChanged: (value) => notifier.update(
                      settings.copyWith(autoPlayFront: value),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.favoriteReviewAutoPlayBack),
                    value: settings.autoPlayBack,
                    onChanged: (value) =>
                        notifier.update(settings.copyWith(autoPlayBack: value)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                    child: Text(
                      l10n.bookmarkReviewOrder,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s),
                    child: _BookmarkReviewOrderSelector(
                      labels: {
                        FavoriteReviewOrder.smart:
                            l10n.bookmarkReviewOrderSmart,
                        FavoriteReviewOrder.dueAt:
                            l10n.bookmarkReviewOrderDueAt,
                        FavoriteReviewOrder.random:
                            l10n.bookmarkReviewOrderRandom,
                      },
                      selected: settings.order,
                      onSelected: (order) =>
                          notifier.update(settings.copyWith(order: order)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              SettingsSectionCard(
                children: [
                  ExpansionTile(
                    key: const Key('favorite-review-settings-sentence-section'),
                    title: Text(
                      l10n.favoriteReviewSentenceSettings,
                      style: AppTextStyles.sectionHeader(context),
                    ),
                    initiallyExpanded: _sentenceExpanded,
                    onExpansionChanged: (expanded) =>
                        setState(() => _sentenceExpanded = expanded),
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    backgroundColor: AppTheme.settingsExpandedBackground(
                      theme.brightness,
                    ),
                    collapsedBackgroundColor: Colors.transparent,
                    iconColor: theme.colorScheme.onSurfaceVariant,
                    collapsedIconColor: theme.colorScheme.onSurfaceVariant,
                    children: const [],
                  ),
                  if (_sentenceExpanded) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.autoShowAiExplanationToggle),
                      value: sentenceSettings.autoShowAiExplanation,
                      onChanged: (value) => sentenceNotifier.update(
                        sentenceSettings.copyWith(autoShowAiExplanation: value),
                      ),
                    ),
                    if (sentenceSettings.autoShowAiExplanation)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.l),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              _AiExplanationSubSwitch(
                                title: l10n.autoShowAiAnalysisToggle,
                                value: sentenceSettings.autoShowAiAnalysis,
                                onChanged: (value) => sentenceNotifier.update(
                                  sentenceSettings.copyWith(
                                    autoShowAiAnalysis: value,
                                  ),
                                ),
                              ),
                              _AiExplanationSubSwitch(
                                title: l10n.autoShowAiTranslationToggle,
                                value: sentenceSettings.autoShowAiTranslation,
                                onChanged: (value) => sentenceNotifier.update(
                                  sentenceSettings.copyWith(
                                    autoShowAiTranslation: value,
                                  ),
                                ),
                              ),
                              _AiExplanationSubSwitch(
                                title: l10n.autoShowAiSenseGroupsToggle,
                                value: sentenceSettings.autoShowAiSenseGroups,
                                onChanged: (value) => sentenceNotifier.update(
                                  sentenceSettings.copyWith(
                                    autoShowAiSenseGroups: value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  ExpansionTile(
                    key: const Key(
                      'favorite-review-settings-vocabulary-section',
                    ),
                    title: Text(
                      l10n.favoriteReviewVocabularySettings,
                      style: AppTextStyles.sectionHeader(context),
                    ),
                    initiallyExpanded: _vocabularyExpanded,
                    onExpansionChanged: (expanded) =>
                        setState(() => _vocabularyExpanded = expanded),
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    backgroundColor: AppTheme.settingsExpandedBackground(
                      theme.brightness,
                    ),
                    collapsedBackgroundColor: Colors.transparent,
                    iconColor: theme.colorScheme.onSurfaceVariant,
                    collapsedIconColor: theme.colorScheme.onSurfaceVariant,
                    children: const [],
                  ),
                  if (_vocabularyExpanded)
                    Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.autoShowAiExplanationToggle),
                          value: settings.autoShowAiLookup,
                          onChanged: (value) => notifier.update(
                            settings.copyWith(autoShowAiLookup: value),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    contentPadding: const EdgeInsets.only(left: AppSpacing.s),
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

  final Map<FavoriteReviewOrder, String> labels;
  final FavoriteReviewOrder selected;
  final ValueChanged<FavoriteReviewOrder> onSelected;

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
