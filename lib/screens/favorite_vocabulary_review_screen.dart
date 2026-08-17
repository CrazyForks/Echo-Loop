/// 收藏词汇极简闪卡复习页面（本步仅实现正面 + 反面占位）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../features/chatbot/widgets/sentence_chat_button.dart';
import '../features/auth/sign_in_required_dialog.dart';
import '../features/subscription/widgets/feature_gate.dart';
import '../features/memory_scheduler/domain/memory_rating.dart';
import '../features/memory_scheduler/domain/memory_scheduler_results.dart';
import '../features/scheduled_flashcard/widgets/flashcard_rating_action_bar.dart';
import '../providers/learning_session/favorite_vocabulary_review_provider.dart';
import '../providers/favorite_review_settings_provider.dart';
import '../providers/dictionary/lookup_controller.dart';
import '../providers/dictionary/dictionary_registry.dart';
import '../providers/pronunciation/pronunciation_providers.dart';
import '../database/providers.dart';
import '../models/dictionary/dictionary_lookup_result.dart';
import '../models/flashcard_item.dart';
import '../router/app_router.dart';
import '../widgets/dictionary/ai_dict_result_view.dart';
import '../widgets/dictionary/local_dict_result_view.dart';
import '../widgets/dictionary/pronunciation_controls.dart';
import '../services/dictionary/dictionary_source.dart';
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
                              key: ValueKey(card.dbKey),
                              card: card,
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
class _VocabularyBack extends ConsumerStatefulWidget {
  const _VocabularyBack({
    super.key,
    required this.card,
    required this.preview,
    required this.showNextReviewTime,
    required this.isSubmitting,
    required this.onRating,
  });

  final FlashcardItem card;
  final MemoryRatingPreviewSet? preview;
  final bool showNextReviewTime;
  final bool isSubmitting;
  final ValueChanged<MemoryRating> onRating;

  @override
  ConsumerState<_VocabularyBack> createState() => _VocabularyBackState();
}

class _VocabularyBackState extends ConsumerState<_VocabularyBack> {
  bool _showAi = false;

  bool get _isSingleWord =>
      !widget.card.displayText.trim().contains(RegExp(r'\s')) &&
      widget.card is FlashcardWordItem;

  Future<void> _playSource() async {
    await ref
        .read(favoriteVocabularyReviewProvider.notifier)
        .playSourceSentence();
  }

  Future<void> _signInAndRetryAi() async {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = await ensureSignedInForAction(
      context: context,
      ref: ref,
      title: l10n.senseGroupSignInRequiredTitle,
      message: l10n.senseGroupSignInRequiredMessage,
    );
    if (!signedIn || !mounted) return;
    ref
        .read(
          dictionaryLookupControllerProvider(
            widget.card.displayText,
            preferredSourceId: 'ai',
          ).notifier,
        )
        .retry();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final card = widget.card;
    final pronunciationClips = _isSingleWord
        ? ref.watch(pronunciationClipsProvider(card.displayText))
        : const [];
    final aiLookup = _showAi
        ? ref.watch(
            dictionaryLookupControllerProvider(
              card.displayText,
              preferredSourceId: 'ai',
            ),
          )
        : null;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.m,
              AppSpacing.l,
              AppSpacing.s,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        card.displayText,
                        key: const Key('favorite-vocabulary-review-back-word'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    // 多发音 badge 已提供逐条播放，标题行不再重复提供总播放入口。
                    if (pronunciationClips.length <= 1)
                      IconButton(
                        key: const Key('favorite-vocabulary-review-word-speak'),
                        tooltip: '播放发音',
                        onPressed: () => unawaited(
                          ref
                              .read(favoriteVocabularyReviewProvider.notifier)
                              .replayCurrent(),
                        ),
                        icon: const Icon(Icons.volume_up_outlined),
                      ),
                  ],
                ),
                if (_isSingleWord) ...[
                  const SizedBox(height: AppSpacing.s),
                  _LocalDictionarySection(word: card.displayText),
                ],
                if (card.sentenceText?.trim() case final String sentenceText
                    when sentenceText.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.m),
                  const Divider(),
                  const SizedBox(height: AppSpacing.s),
                  InkWell(
                    key: const Key('favorite-vocabulary-review-source'),
                    onTap: _playSource,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.play_circle_outline, size: 20),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(
                            child: Text(
                              sentenceText,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (card.audioItemId case final String audioItemId) ...[
                  const SizedBox(height: AppSpacing.s),
                  _SourceMaterialLink(audioItemId: audioItemId),
                ],
                const SizedBox(height: AppSpacing.m),
                OutlinedButton.icon(
                  key: const Key('favorite-vocabulary-review-ai-toggle'),
                  onPressed: () => setState(() => _showAi = !_showAi),
                  icon: Icon(
                    _showAi
                        ? Icons.keyboard_arrow_up
                        : Icons.auto_awesome_outlined,
                  ),
                  label: Text(_showAi ? '收起 AI 查词' : '显示 AI 查词'),
                ),
                if (_showAi) ...[
                  const SizedBox(height: AppSpacing.s),
                  AiDictResultView(
                    state: aiLookup?.current,
                    onRetry: () => ref
                        .read(
                          dictionaryLookupControllerProvider(
                            card.displayText,
                            preferredSourceId: 'ai',
                          ).notifier,
                        )
                        .retry(),
                    onSignIn: () => unawaited(_signInAndRetryAi()),
                    onUpgrade: () => unawaited(openPaywall(context, ref)),
                  ),
                ],
              ],
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
                    showNextReviewTime: widget.showNextReviewTime,
                    dueAt: widget.preview?.again.dueAt,
                  ),
                ),
                FlashcardRatingAction(
                  rating: MemoryRating.good,
                  emoji: '🙂',
                  label: l10n.bookmarkReviewRatingGood,
                  detail: formatNextReviewTimeDetail(
                    context,
                    showNextReviewTime: widget.showNextReviewTime,
                    dueAt: widget.preview?.good.dueAt,
                  ),
                ),
                FlashcardRatingAction(
                  rating: MemoryRating.easy,
                  emoji: '😎',
                  label: l10n.bookmarkReviewRatingEasy,
                  detail: formatNextReviewTimeDetail(
                    context,
                    showNextReviewTime: widget.showNextReviewTime,
                    dueAt: widget.preview?.easy.dueAt,
                  ),
                ),
              ],
              enabled: widget.preview != null && !widget.isSubmitting,
              onSelected: (action) => widget.onRating(action.rating),
            ),
          ),
        ),
      ],
    );
  }
}

/// 单词背面直接查询本地源，不继承查词面板的默认源与会话偏好。
class _LocalDictionarySection extends ConsumerStatefulWidget {
  const _LocalDictionarySection({required this.word});

  final String word;

  @override
  ConsumerState<_LocalDictionarySection> createState() =>
      _LocalDictionarySectionState();
}

class _LocalDictionarySectionState
    extends ConsumerState<_LocalDictionarySection> {
  late Future<DictionaryLookupResult?> _lookup = _startLookup();

  Future<DictionaryLookupResult?> _startLookup() => ref
      .read(localDictionarySourceProvider)
      .lookup(DictionaryLookupRequest(word: widget.word));

  @override
  void didUpdateWidget(_LocalDictionarySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word != widget.word) _lookup = _startLookup();
  }

  @override
  Widget build(BuildContext context) {
    final clips = ref.watch(pronunciationClipsProvider(widget.word));
    return FutureBuilder<DictionaryLookupResult?>(
      future: _lookup,
      builder: (context, snapshot) {
        if (snapshot.data case final LocalDictResult result) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (clips.length > 1) ...[
                PronunciationBadgeGroup(
                  clips: clips,
                  fallbackText: widget.word,
                ),
                const SizedBox(height: AppSpacing.s),
              ],
              LocalDictResultView(
                state: LookupLoaded(result),
                word: widget.word,
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// 来源材料入口只读取标题；播放仍由来源句统一播放编排负责。
class _SourceMaterialLink extends ConsumerWidget {
  const _SourceMaterialLink({required this.audioItemId});

  final String audioItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: ref.read(audioItemDaoProvider).getById(audioItemId),
    builder: (context, snapshot) {
      final title = snapshot.data?.name ?? '来源材料';
      return InkWell(
        key: const Key('favorite-vocabulary-review-source-material'),
        onTap: () => context.push(AppRoutes.audioLearningPlan(audioItemId)),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.headphones_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      );
    },
  );
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
