/// 收藏词汇极简闪卡复习页面（本步仅实现正面 + 反面占位）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../features/chatbot/widgets/sentence_chat_button.dart';
import '../features/memory_scheduler/domain/memory_rating.dart';
import '../features/memory_scheduler/domain/memory_scheduler_results.dart';
import '../features/scheduled_flashcard/widgets/flashcard_rating_action_bar.dart';
import '../providers/learning_session/favorite_vocabulary_review_provider.dart';
import '../providers/favorite_review_settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../utils/wakelock_mixin.dart';
import '../widgets/bookmark_review/bookmark_review_settings_sheet.dart';

class FavoriteVocabularyReviewScreen extends ConsumerStatefulWidget {
  const FavoriteVocabularyReviewScreen({super.key});

  @override
  ConsumerState<FavoriteVocabularyReviewScreen> createState() =>
      _FavoriteVocabularyReviewScreenState();
}

class _FavoriteVocabularyReviewScreenState
    extends ConsumerState<FavoriteVocabularyReviewScreen>
    with WakelockMixin {
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref
              .read(favoriteVocabularyReviewProvider.notifier)
              .startCurrentCard(),
        );
      }
    });
  }

  Future<void> _exit() async {
    if (_isExiting) return;
    _isExiting = true;
    await ref.read(favoriteVocabularyReviewProvider.notifier).disposeSession();
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _openSettings() async {
    await ref
        .read(favoriteVocabularyReviewProvider.notifier)
        .interruptPlayback();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const BookmarkReviewSettingsSheet(
        task: FavoriteReviewSettingsTask.vocabulary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoriteVocabularyReviewProvider);
    final card = state.currentCard;
    final l10n = AppLocalizations.of(context)!;
    final player = ref.read(favoriteVocabularyReviewProvider.notifier);

    return wakelockBody(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          unawaited(_exit());
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const Key('favorite-vocabulary-review-close'),
              onPressed: _exit,
              icon: const Icon(Icons.close),
            ),
            title: Text(l10n.favoriteVocabularyReviewTitle),
            centerTitle: true,
            actions: [
              SentenceChatButton(
                sentenceText: card?.displayText ?? '',
                onBeforeOpen: () => unawaited(player.interruptPlayback()),
              ),
              IconButton(
                key: const Key('favorite-vocabulary-review-settings'),
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          body: card == null
              ? _EmptyReview(message: l10n.favoriteVocabularyReviewEmpty)
              : Column(
                  children: [
                    _ReviewProgress(
                      progress: state.total == 0
                          ? 0
                          : state.position / state.total,
                    ),
                    Expanded(
                      child: state.face == FavoriteVocabularyReviewFace.front
                          ? _VocabularyFront(
                              playbackState: state.playbackState,
                              hasError: state.mediaError != null,
                              onReplay: () => unawaited(player.replayCurrent()),
                              onReveal: () => unawaited(player.revealBack()),
                            )
                          : _VocabularyBack(
                              word: card.displayText,
                              preview: state.preview,
                              showNextReviewTime: ref.watch(
                                favoriteReviewSettingsProvider.select(
                                  (settings) => settings.showNextReviewTime,
                                ),
                              ),
                              isSubmitting: state.isSubmittingRating,
                              onRating: (rating) =>
                                  unawaited(player.selectRating(rating)),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ReviewProgress extends StatelessWidget {
  const _ReviewProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.s,
      ),
      child: LinearProgressIndicator(
        key: const Key('favorite-vocabulary-review-progress'),
        value: progress,
        minHeight: 3,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _VocabularyFront extends StatelessWidget {
  const _VocabularyFront({
    required this.playbackState,
    required this.hasError,
    required this.onReplay,
    required this.onReveal,
  });

  final FavoriteVocabularyReviewPlaybackState playbackState;
  final bool hasError;
  final VoidCallback onReplay;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final status = switch (playbackState) {
      FavoriteVocabularyReviewPlaybackState.loading =>
        l10n.favoriteVocabularyReviewLoadingAudio,
      FavoriteVocabularyReviewPlaybackState.playing =>
        l10n.favoriteVocabularyReviewPlaying,
      FavoriteVocabularyReviewPlaybackState.failed =>
        l10n.favoriteVocabularyReviewTapRetry,
      FavoriteVocabularyReviewPlaybackState.idle =>
        l10n.favoriteVocabularyReviewTapReplay,
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.m,
            AppSpacing.s,
            AppSpacing.m,
            AppSpacing.l,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: Material(
                    key: const Key('favorite-vocabulary-review-listen-zone'),
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.2 : 0.42,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onReplay,
                      child: SizedBox.expand(
                        child: _CenteredPrompt(
                          icon: hasError
                              ? Icons.refresh_rounded
                              : Icons.volume_up_rounded,
                          title: status,
                          body: hasError
                              ? l10n.favoriteVocabularyReviewAudioSkipped
                              : l10n.favoriteVocabularyReviewTapReplay,
                          accent: hasError
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Expanded(
                  flex: 1,
                  child: Material(
                    key: const Key('favorite-vocabulary-review-reveal-zone'),
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(28),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onReveal,
                      child: SizedBox.expand(
                        child: _CenteredPrompt(
                          icon: Icons.visibility_outlined,
                          title: l10n.favoriteVocabularyReviewReadyTitle,
                          body: l10n.favoriteVocabularyReviewRevealHint,
                          accent: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredPrompt extends StatelessWidget {
  const _CenteredPrompt({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - AppSpacing.m * 2).clamp(
            0,
            double.infinity,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(icon, size: 28, color: accent),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 词汇背面本步只显示收藏文本，内容扩展留待后续任务。
class _VocabularyBack extends StatelessWidget {
  const _VocabularyBack({
    required this.word,
    required this.preview,
    required this.showNextReviewTime,
    required this.isSubmitting,
    required this.onRating,
  });

  final String word;
  final MemoryRatingPreviewSet? preview;
  final bool showNextReviewTime;
  final bool isSubmitting;
  final ValueChanged<MemoryRating> onRating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Text(
                word,
                key: const Key('favorite-vocabulary-review-back-word'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: FlashcardRatingActionBar(
              actions: [
                FlashcardRatingAction(
                  rating: MemoryRating.again,
                  emoji: '😕',
                  label: l10n.bookmarkReviewRatingAgain,
                  detail: formatNextReviewTimeDetail(
                    context,
                    showNextReviewTime: showNextReviewTime,
                    dueAt: preview?.again.dueAt,
                  ),
                ),
                FlashcardRatingAction(
                  rating: MemoryRating.good,
                  emoji: '🙂',
                  label: l10n.bookmarkReviewRatingGood,
                  detail: formatNextReviewTimeDetail(
                    context,
                    showNextReviewTime: showNextReviewTime,
                    dueAt: preview?.good.dueAt,
                  ),
                ),
                FlashcardRatingAction(
                  rating: MemoryRating.easy,
                  emoji: '😎',
                  label: l10n.bookmarkReviewRatingEasy,
                  detail: formatNextReviewTimeDetail(
                    context,
                    showNextReviewTime: showNextReviewTime,
                    dueAt: preview?.easy.dueAt,
                  ),
                ),
              ],
              enabled: preview != null && !isSubmitting,
              onSelected: (action) => onRating(action.rating),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.m),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}
