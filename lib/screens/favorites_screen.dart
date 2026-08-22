/// 收藏页面
///
/// 聚合两类核心资产：收藏句子（按音频分组）和收藏单词（按时间倒序）。
/// 通过 SegmentedButton 在句子/单词视图间切换。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../analytics/models/event_names.dart';
import '../features/usage/usage_event.dart';
import '../features/usage/usage_providers.dart';
import '../database/app_database.dart';
import '../database/daos/bookmark_dao.dart';
import '../database/providers.dart';
import '../l10n/app_localizations.dart';
import '../models/dict_entry.dart';
import '../screens/sentence_detail_screen.dart';
import '../providers/short_audio_player_provider.dart';
import '../providers/tts/tts_controller_provider.dart';
import '../providers/pronunciation/pronunciation_providers.dart';
import '../widgets/tts/speak_button.dart';
import '../providers/learning_session/bookmark_review_provider.dart';
import '../providers/learning_session/favorite_vocabulary_review_provider.dart';
import '../providers/learning_session/favorite_review_due_count_provider.dart';
import '../providers/new_user_guide_provider.dart';
import '../providers/saved_sense_group_provider.dart';
import '../providers/saved_word_provider.dart';
import '../services/dictionary_service.dart';
import '../services/app_logger.dart';
import '../services/pronunciation/source_sentence_player.dart';
import '../services/pronunciation/local_audio_range_player.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/favorites/sentence_recycle_bin_sheet.dart';
import '../widgets/favorites/vocabulary_recycle_bin_sheet.dart';
import '../widgets/bookmark_review/bookmark_review_settings_sheet.dart';
import '../widgets/guide_flow.dart';

/// 判断 tile 是否真实位于最近滚动视口内；`cacheExtent` 保留的离屏 widget 不预热。
bool _isInScrollableViewport(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return false;
  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (viewport is! RenderBox) return true;
  // RenderAbstractViewport 的公开工厂返回抽象类型；实际滚动视口同时是 RenderBox。
  final viewportBox = viewport as RenderBox;
  if (!viewportBox.hasSize) return true;
  final rect = MatrixUtils.transformRect(
    renderObject.getTransformTo(viewportBox),
    Offset.zero & renderObject.size,
  );
  return (Offset.zero & viewportBox.size).overlaps(rect);
}

/// 收藏页面视图模式
enum _FavoritesView { sentences, words }

Future<bool> _playSourceSentence(
  WidgetRef ref, {
  required String key,
  required String? audioItemId,
  required int? sentenceIndex,
  required String? sentenceText,
  required int? sentenceStartMs,
  required int? sentenceEndMs,
}) {
  AppLogger.log(
    'FavoritesPlayback',
    'source request key=$key text="$sentenceText" audio=$audioItemId',
  );
  final player = SourceSentencePlayer(
    audioItemDao: ref.read(audioItemDaoProvider),
    audioClipPlayer: ref.read(shortAudioPlayerProvider),
    speak: (text, playbackKey) =>
        ref.read(ttsControllerProvider.notifier).speak(text, key: playbackKey),
  );
  return player.play(
    audioItemId: audioItemId,
    sentenceIndex: sentenceIndex,
    sentenceText: sentenceText,
    sentenceStartMs: sentenceStartMs,
    sentenceEndMs: sentenceEndMs,
    playbackKey: key,
  );
}

/// 收藏页面
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  _FavoritesView _currentView = _FavoritesView.sentences;

  /// 新手引导 step key（生命周期内稳定）
  final GlobalKey _keySentencesList = GlobalKey();
  final GlobalKey _keySentencesReviewBtn = GlobalKey();
  final GlobalKey _keyWordsList = GlobalKey();
  final GlobalKey _keyVocabReviewBtn = GlobalKey();

  /// 打开收藏复习共享设置；收藏页不预展开任一内容分区。
  Future<void> _openReviewSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => BookmarkReviewSettingsSheet(
        task: FavoriteReviewSettingsTask.favorites,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // 获取收藏数量
    final bookmarksAsync = ref.watch(bookmarkListProvider);
    final sentenceCount = bookmarksAsync.valueOrNull?.length;
    final wordCount = ref.watch(savedWordListProvider).valueOrNull?.length ?? 0;
    final phraseCount =
        ref.watch(savedSenseGroupListProvider).valueOrNull?.length ?? 0;
    final vocabCount = wordCount + phraseCount;

    final sentenceLabel = sentenceCount != null && sentenceCount > 0
        ? '${l10n.favoritesSentences} ($sentenceCount)'
        : l10n.favoritesSentences;
    final wordLabel = vocabCount > 0
        ? '${l10n.favoritesVocabulary} ($vocabCount)'
        : l10n.favoritesVocabulary;

    // ----- 新手引导 flow 声明 -----
    // 句子列表描述中嵌入真实的哑铃图标，让用户更易辨识 tap 目标
    const iconPlaceholder = '{ICON}';
    final sentencesListDescRaw = l10n.guideFavoritesSentencesListDescription(
      iconPlaceholder,
    );
    final sentencesListDescParts = sentencesListDescRaw.split(iconPlaceholder);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tooltipDescColor = isDark
        ? const Color(0xFF9BA3AE)
        : const Color(0xFF5A6270);
    final stepSentencesList = GuideStep(
      key: _keySentencesList,
      description: sentencesListDescRaw,
      descriptionWidget: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: sentencesListDescParts[0]),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                Icons.fitness_center,
                size: 15,
                color: theme.colorScheme.primary,
              ),
            ),
            if (sentencesListDescParts.length > 1)
              TextSpan(text: sentencesListDescParts[1]),
          ],
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            fontWeight: FontWeight.w400,
            color: tooltipDescColor,
          ),
        ),
      ),
    );
    final stepSentencesReviewBtn = GuideStep(
      key: _keySentencesReviewBtn,
      description: l10n.guideFavoritesSentencesReviewDescription,
    );
    final stepWordsList = GuideStep(
      key: _keyWordsList,
      description: l10n.guideFavoritesVocabularyListDescription,
    );
    final stepFlashcardBtn = GuideStep(
      key: _keyVocabReviewBtn,
      description: l10n.guideFavoritesFlashcardDescription,
    );

    // 有效书签：过滤迁移遗留的无时长或空文本条目（复用 _FloatingSentenceReviewButton 同一规则）
    final allBookmarks = bookmarksAsync.valueOrNull ?? const [];
    final hasValidSentences = allBookmarks.any(
      (b) =>
          (b.bookmark.endTime - b.bookmark.startTime) > 0 &&
          b.bookmark.sentenceText.isNotEmpty,
    );
    final hasVocab = vocabCount > 0;
    final flows = <GuideFlow>[
      GuideFlow(
        flowId: GuideFlowIds.favoritesSentencesReview,
        shouldRun:
            _currentView == _FavoritesView.sentences && hasValidSentences,
        steps: [stepSentencesList, stepSentencesReviewBtn],
      ),
      GuideFlow(
        flowId: GuideFlowIds.favoritesVocabularyReview,
        shouldRun: _currentView == _FavoritesView.words && hasVocab,
        steps: [stepWordsList, stepFlashcardBtn],
      ),
    ];

    return GuideFlowSequenceHost(
      flows: flows,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.favorites),
          actions: [
            IconButton(
              key: const Key('favorites-statistics'),
              icon: SvgPicture.asset(
                'assets/icon/bar-chart.svg',
                width: 21,
                height: 21,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.onSurfaceVariant,
                  BlendMode.srcIn,
                ),
              ),
              tooltip: '复习统计',
              onPressed: () => context.push(AppRoutes.reviewStatistics),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.restore),
                tooltip: l10n.recycleBinTitle,
                onPressed: () {
                  if (_currentView == _FavoritesView.sentences) {
                    showSentenceRecycleBinSheet(context: context);
                  } else {
                    showVocabularyRecycleBinSheet(context: context);
                  }
                },
              ),
            ),
            IconButton(
              key: const Key('favorites-review-settings'),
              icon: const Icon(Icons.tune),
              tooltip: l10n.bookmarkReviewSettingsTitle,
              onPressed: _openReviewSettings,
            ),
          ],
        ),
        body: Column(
          children: [
            // SegmentedButton 切换
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_FavoritesView>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _FavoritesView.sentences,
                      label: Text(sentenceLabel),
                      icon: const Icon(Icons.format_quote, size: 18),
                    ),
                    ButtonSegment(
                      value: _FavoritesView.words,
                      label: Text(wordLabel),
                      icon: const Icon(Icons.abc, size: 18),
                    ),
                  ],
                  selected: {_currentView},
                  onSelectionChanged: (selected) {
                    debugPrint('[PERF] tab 切换: ${selected.first}');
                    final sw = Stopwatch()..start();
                    setState(() => _currentView = selected.first);
                    debugPrint(
                      '[PERF] setState 完成: ${sw.elapsedMilliseconds}ms',
                    );
                  },
                  style: SegmentedButton.styleFrom(
                    textStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // 内容区域（Stack：列表 + 底部悬浮按钮）
            Expanded(
              child: Stack(
                children: [
                  // 列表（IndexedStack 保留两个 tab 的状态，切换不重建）
                  IndexedStack(
                    index: _currentView.index,
                    children: [
                      _SentencesView(firstItemStep: stepSentencesList),
                      _WordsView(
                        firstItemStep: stepWordsList,
                        // 仅词汇 tab 激活时才预热（IndexedStack 会同时构建两个 tab，
                        // 不门控则停在句子 tab 也会为词汇起引擎合成、浪费 CPU）。
                        isActive: _currentView == _FavoritesView.words,
                      ),
                    ],
                  ),

                  // 底部悬浮复习按钮
                  if (_currentView == _FavoritesView.sentences)
                    _FloatingSentenceReviewButton(
                      guideStep: stepSentencesReviewBtn,
                    )
                  else if (_currentView == _FavoritesView.words)
                    _FloatingFlashcardButton(guideStep: stepFlashcardBtn),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 句子视图
// ============================================================

/// 句子视图 — 按音频分组展示收藏的书签句子
class _SentencesView extends ConsumerStatefulWidget {
  /// 新手引导高亮目标：只包第一个音频分组卡片
  final GuideStep? firstItemStep;

  const _SentencesView({this.firstItemStep});

  @override
  ConsumerState<_SentencesView> createState() => _SentencesViewState();
}

class _SentencesViewState extends ConsumerState<_SentencesView> {
  /// 首个分组卡片的展开控制器：引导激活时自动展开
  final ExpansibleController _firstGroupController = ExpansibleController();

  @override
  void initState() {
    super.initState();
    // 引导 flow 激活时主动展开第一条，让用户更直观看到内部内容
    ref.listenManual<GuideControllerState>(guideControllerProvider, (
      prev,
      next,
    ) {
      if (next.activeFlowId != GuideFlowIds.favoritesSentencesReview) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_firstGroupController.isExpanded) return;
        _firstGroupController.expand();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookmarksAsync = ref.watch(bookmarkListProvider);

    return bookmarksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (allBookmarks) {
        if (allBookmarks.isEmpty) {
          return _buildEmptyState(context, isSentences: true);
        }

        // 按音频名称分组
        final grouped = <String, List<BookmarkWithAudio>>{};
        for (final item in allBookmarks) {
          (grouped[item.bookmark.audioItemId] ??= []).add(item);
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.m,
            AppSpacing.s,
            AppSpacing.m,
            80, // 底部留出悬浮按钮空间
          ),
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final audioId = grouped.keys.elementAt(index);
            final items = grouped[audioId]!;
            final audioName = items.first.audioName;
            final isFirst = index == 0;

            final tile = _AudioBookmarkGroup(
              audioId: audioId,
              audioName: audioName,
              bookmarks: items,
              expansionController: isFirst ? _firstGroupController : null,
            );
            if (isFirst && widget.firstItemStep != null) {
              return GuideTarget(step: widget.firstItemStep!, child: tile);
            }
            return tile;
          },
        );
      },
    );
  }
}

/// 底部悬浮句子复习按钮
class _FloatingSentenceReviewButton extends ConsumerWidget {
  /// 新手引导高亮 step，用于包裹按钮（仅有效书签非空时才渲染）
  final GuideStep? guideStep;

  const _FloatingSentenceReviewButton({this.guideStep});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allBookmarks = ref.watch(bookmarkListProvider).valueOrNull ?? [];
    if (allBookmarks.isEmpty) return const SizedBox.shrink();

    // 过滤掉无效书签（迁移遗留的无时长条目）
    final validBookmarks = allBookmarks.where((b) {
      final duration = b.bookmark.endTime - b.bookmark.startTime;
      return duration > 0 && b.bookmark.sentenceText.isNotEmpty;
    }).toList();
    if (validBookmarks.isEmpty) return const SizedBox.shrink();

    final dueCountAsync = ref.watch(favoriteSentenceDueCountProvider);
    final dueCount = dueCountAsync.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    return _FloatingReviewButton(
      icon: Icons.fitness_center,
      guideStep: guideStep,
      // 待复习数量尚未加载时不回退显示总收藏数，避免切换 Tab 时文案闪烁。
      label: dueCount == null
          ? l10n.downloadLoading
          : dueCount == 0
          ? l10n.bookmarkReviewNothingToReview
          : l10n.bookmarkReviewDueCount(dueCount),
      enabled: dueCount != null && dueCount > 0,
      onPressed: () async {
        ref
            .read(usageTrackerProvider)
            .record(
              UsageEvent.bookmarkReviewButtonTapped,
              analyticsParams: {
                EventParams.totalSentencesCount: validBookmarks.length,
              },
            );
        final sw = Stopwatch()..start();
        final provider = ref.read(bookmarkReviewProvider.notifier);
        debugPrint(
          '[PERF] bookmark review read providers: ${sw.elapsedMilliseconds}ms',
        );
        await provider.initialize(allBookmarks);
        debugPrint(
          '[PERF] bookmark review initialize: ${sw.elapsedMilliseconds}ms',
        );
        if (!context.mounted) return;
        context.push(AppRoutes.bookmarkReview);
        debugPrint(
          '[PERF] context.push bookmarkReview: ${sw.elapsedMilliseconds}ms',
        );
      },
    );
  }
}

/// 底部悬浮 Flashcard 按钮
class _FloatingFlashcardButton extends ConsumerWidget {
  /// 新手引导高亮 step，仅当按钮真正渲染时才包裹
  final GuideStep? guideStep;

  const _FloatingFlashcardButton({this.guideStep});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedWordsAsync = ref.watch(savedWordListProvider);
    final savedPhrasesAsync = ref.watch(savedSenseGroupListProvider);

    final words = savedWordsAsync.valueOrNull ?? [];
    final phrases = savedPhrasesAsync.valueOrNull ?? [];
    final totalCount = words.length + phrases.length;

    if (totalCount == 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final dueCountAsync = ref.watch(favoriteVocabularyDueCountProvider);
    final dueCount = dueCountAsync.valueOrNull;
    return _FloatingReviewButton(
      icon: Icons.style_outlined,
      guideStep: guideStep,
      // 待复习数量尚未加载时不回退显示总收藏数，避免切换 Tab 时文案闪烁。
      label: dueCount == null
          ? l10n.downloadLoading
          : dueCount == 0
          ? l10n.favoriteReviewNothingToReview
          : l10n.favoriteVocabularyReviewDueCount(dueCount),
      enabled: dueCount != null && dueCount > 0,
      onPressed: () async {
        ref
            .read(usageTrackerProvider)
            .record(
              UsageEvent.flashcardButtonTapped,
              analyticsParams: {EventParams.totalCards: totalCount},
            );
        await ref
            .read(favoriteVocabularyReviewProvider.notifier)
            .initialize(words, phrases);
        if (context.mounted) {
          context.push(AppRoutes.favoriteVocabularyReview);
        }
      },
    );
  }
}

/// 底部悬浮复习按钮 — 渐变遮罩 + 全宽 FilledButton
class _FloatingReviewButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// 新手引导高亮 step，仅包裹按钮区域（不含渐变遮罩）
  final GuideStep? guideStep;
  final bool enabled;

  const _FloatingReviewButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.guideStep,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget button = SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
    if (guideStep != null) {
      button = GuideTarget(step: guideStep!, child: button);
    }

    final buttonBox = Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        0,
        AppSpacing.l,
        AppSpacing.m,
      ),
      child: button,
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 渐变遮罩
          IgnorePointer(
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surface.withValues(alpha: 0.0),
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
          // 按钮区域
          buttonBox,
        ],
      ),
    );
  }
}

/// 单个音频的书签分组卡片
class _AudioBookmarkGroup extends ConsumerWidget {
  final String audioId;
  final String audioName;
  final List<BookmarkWithAudio> bookmarks;

  /// 展开控制器（可选）：用于新手引导时由外部主动展开
  final ExpansibleController? expansionController;

  const _AudioBookmarkGroup({
    required this.audioId,
    required this.audioName,
    required this.bookmarks,
    this.expansionController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        controller: expansionController,
        initiallyExpanded: false,
        iconColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        collapsedIconColor: theme.colorScheme.onSurfaceVariant.withValues(
          alpha: 0.4,
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        title: Row(
          children: [
            Expanded(
              child: Text(
                audioName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              l10n.favoritesBookmarkCount(bookmarks.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            // 练习该音频收藏句按钮
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: const Icon(Icons.fitness_center, size: 18),
                color: theme.colorScheme.primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () async {
                  final provider = ref.read(bookmarkReviewProvider.notifier);
                  await provider.initialize(bookmarks);
                  if (!context.mounted) return;
                  context.push(AppRoutes.bookmarkReview);
                },
              ),
            ),
          ],
        ),
        children: [
          for (int i = 0; i < bookmarks.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: AppSpacing.m,
                endIndent: AppSpacing.m,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            _BookmarkSentenceTile(
              bookmark: bookmarks[i].bookmark,
              audioId: audioId,
              audioName: audioName,
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条书签句子列表项（可展开查看翻译/解析，支持播放和点词查词典）
class _BookmarkSentenceTile extends ConsumerStatefulWidget {
  final Bookmark bookmark;
  final String audioId;
  final String audioName;

  const _BookmarkSentenceTile({
    required this.bookmark,
    required this.audioId,
    required this.audioName,
  });

  @override
  ConsumerState<_BookmarkSentenceTile> createState() =>
      _BookmarkSentenceTileState();
}

class _BookmarkSentenceTileState extends ConsumerState<_BookmarkSentenceTile> {
  /// 播放该句子的原声片段
  Future<void> _playSentence() async {
    final key = 'saved-sentence:${widget.bookmark.id}';
    final player = ref.read(shortAudioPlayerProvider);
    if (player.state.playingKey == key) {
      await player.stop();
      return;
    }
    try {
      final start = Duration(
        milliseconds: (widget.bookmark.startTime * 1000).round(),
      );
      final end = Duration(
        milliseconds: (widget.bookmark.endTime * 1000).round(),
      );
      await LocalAudioRangePlayer(
        audioItemDao: ref.read(audioItemDaoProvider),
        audioClipPlayer: player,
      ).play(
        audioItemId: widget.audioId,
        start: start,
        end: end,
        playbackKey: key,
      );
    } catch (_) {
      // 忽略播放错误（音频文件不存在等）
    }
  }

  /// 跳转到句子详情页（单句精听）
  void _openDetail() {
    final bm = widget.bookmark;
    AppRoutes.pushNested(
      context,
      AppRoutes.sentenceDetailSegment,
      extra: SentenceDetailArgs(
        audioItemId: widget.audioId,
        audioName: widget.audioName,
        sentenceText: bm.sentenceText,
        sentenceIndex: bm.sentenceIndex,
        startTimeMs: (bm.startTime * 1000).round(),
        endTimeMs: (bm.endTime * 1000).round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playingKey = ref
        .watch(shortAudioPlaybackStateProvider)
        .valueOrNull
        ?.playingKey;
    final theme = Theme.of(context);
    final bm = widget.bookmark;

    // 提前捕获 DAO，避免 Dismissible 销毁 widget 后 ref 失效
    final bookmarkDao = ref.read(bookmarkDaoProvider);

    return Dismissible(
      key: ValueKey('bookmark_${bm.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.l),
        color: theme.colorScheme.error,
        child: Icon(Icons.bookmark_remove, color: theme.colorScheme.onError),
      ),
      onDismissed: (_) {
        bookmarkDao.removeBookmark(widget.audioId, bm.sentenceIndex);
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
        leading: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            playingKey == 'saved-sentence:${bm.id}'
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outline,
            size: 28,
          ),
          color: playingKey == 'saved-sentence:${bm.id}'
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
          onPressed: _playSentence,
        ),
        title: Text(bm.sentenceText, style: theme.textTheme.bodyMedium),
        trailing: SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            onPressed: _openDetail,
          ),
        ),
        onTap: _playSentence,
      ),
    );
  }
}

// ============================================================
// 单词视图
// ============================================================

/// 单词视图 — 按收藏时间倒序展示
///
/// 批量预加载字典释义，所有释义一次性渲染（不会逐个闪烁）。
class _WordsView extends ConsumerStatefulWidget {
  /// 新手引导高亮目标：只包第一个词汇 tile
  final GuideStep? firstItemStep;

  /// 词汇 tab 当前是否激活（IndexedStack 会同时构建两个 tab，用此门控预热——
  /// 仅激活时才为词汇起引擎合成，停在句子 tab 不预热）。
  final bool isActive;

  const _WordsView({this.firstItemStep, this.isActive = false});

  @override
  ConsumerState<_WordsView> createState() => _WordsViewState();
}

class _WordsViewState extends ConsumerState<_WordsView> {
  /// 批量查询得到的字典条目缓存
  Map<String, DictEntry> _dictMap = {};

  /// 上次触发查询的单词列表，用于去重
  List<String> _lastWordKeys = [];

  /// 首个词汇卡片的展开控制器：引导激活时自动展开
  final ExpansibleController _firstItemController = ExpansibleController();

  /// 统一 TTS 控制器（build 时缓存，供 dispose 取消预热——dispose 内不可用 ref，§7.14）。
  TtsController? _ttsController;
  bool _isScrolling = false;
  int _scrollSession = 0;
  bool _hasWarmedCurrentEngine = false;

  void _scheduleEngineWarmup() {
    if (!widget.isActive || _hasWarmedCurrentEngine) return;
    _hasWarmedCurrentEngine = true;
    final controller = _ttsController;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) {
        controller.warmUpCurrentEngine();
      }
    });
  }

  bool _handleScroll(ScrollNotification notification) {
    if (!widget.isActive) return false;
    if (notification is ScrollStartNotification && !_isScrolling) {
      _isScrolling = true;
      final startedSession = ++_scrollSession;
      AppLogger.log(
        'FavoritesTts',
        'scroll start session=$startedSession: cancel prewarm',
      );
      _ttsController?.cancelTextsPrewarm();
      // 让已创建的 tile 收到 isScrolling=true 并清除提交标记；滚动停止后
      // 才能对当前视口重新提交预热。通知在布局期派发，延后重建避免 frame 异常。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.isActive &&
            _isScrolling &&
            _scrollSession == startedSession) {
          setState(() {});
        }
      });
    } else if (notification is ScrollEndNotification && _isScrolling) {
      _isScrolling = false;
      final completedSession = ++_scrollSession;
      AppLogger.log(
        'FavoritesTts',
        'scroll end session=$completedSession: schedule visible tile prewarm',
      );
      // ScrollEndNotification 可能由 Viewport 布局期间派发，延后重建以避免在布局期
      // 调度 build；会话号确保下一次滚动已开始时不恢复旧视口的预热。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.isActive &&
            !_isScrolling &&
            _scrollSession == completedSession) {
          AppLogger.log(
            'FavoritesTts',
            'scroll restore session=$completedSession: rebuild visible tiles',
          );
          setState(() {});
        } else {
          AppLogger.log(
            'FavoritesTts',
            'scroll restore discarded session=$completedSession '
                'active=${widget.isActive} scrolling=$_isScrolling '
                'current=$_scrollSession',
          );
        }
      });
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual<GuideControllerState>(guideControllerProvider, (
      prev,
      next,
    ) {
      if (next.activeFlowId != GuideFlowIds.favoritesVocabularyReview) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_firstItemController.isExpanded) return;
        _firstItemController.expand();
      });
    });
  }

  @override
  void didUpdateWidget(_WordsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切离词汇 tab（IndexedStack 不销毁本视图）→ 停在途预热；重置签名使重新
    // 激活时可再次触发（届时已缓存的命中即跳过，未完成的续上）。
    if (oldWidget.isActive && !widget.isActive) {
      _ttsController?.cancelTextsPrewarm();
      _hasWarmedCurrentEngine = false;
    }
  }

  @override
  void dispose() {
    // 离开收藏页即停在途预热，避免继续占用 CPU 合成用不到的发音。
    _ttsController?.cancelTextsPrewarm();
    super.dispose();
  }

  /// 当单词列表变化时，批量查询字典释义
  void _loadDictEntries(List<SavedWord> words) {
    final wordStrings = words.map((w) => w.word).toList();
    // 单词列表未变化时跳过
    if (_listEquals(wordStrings, _lastWordKeys)) return;
    _lastWordKeys = wordStrings;

    final entries = DictionaryService.instance.lookupAll(wordStrings);
    if (!mounted) return;
    setState(() => _dictMap = entries);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final savedWordsAsync = ref.watch(savedWordListProvider);
    final savedPhrasesAsync = ref.watch(savedSenseGroupListProvider);

    // 等待两个数据源都加载完成
    if (savedWordsAsync.isLoading || savedPhrasesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (savedWordsAsync.hasError) {
      return Center(child: Text('Error: ${savedWordsAsync.error}'));
    }

    final words = savedWordsAsync.valueOrNull ?? [];
    final phrases = savedPhrasesAsync.valueOrNull ?? [];

    if (words.isEmpty && phrases.isEmpty) {
      return _buildEmptyState(context, isSentences: false);
    }

    // 触发批量字典查询
    _loadDictEntries(words);

    // 合并并按 createdAt 倒序排列
    final items = <_VocabularyItem>[
      for (final w in words) _VocabularyWord(w),
      for (final p in phrases) _VocabularyPhrase(p),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Tile 负责提交自己的预热；父视图保留同一控制器，以便切 tab 或离页时
    // 取消尚未完成的增量预热队列。
    if (widget.isActive) {
      _ttsController = ref.read(ttsControllerProvider.notifier);
      _scheduleEngineWarmup();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          AppSpacing.s,
          AppSpacing.m,
          80,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isFirst = index == 0;
          final controller = isFirst ? _firstItemController : null;
          final tile = switch (item) {
            _VocabularyWord(word: final w) => _SavedWordTile(
              key: ValueKey('w_${w.id}'),
              savedWord: w,
              dictEntry: _dictMap[w.word],
              expansionController: controller,
              isActive: widget.isActive,
              isScrolling: _isScrolling,
            ),
            _VocabularyPhrase(phrase: final p) => _SavedPhraseTile(
              key: ValueKey('p_${p.id}'),
              savedPhrase: p,
              expansionController: controller,
              isActive: widget.isActive,
              isScrolling: _isScrolling,
            ),
          };
          if (isFirst && widget.firstItemStep != null) {
            return GuideTarget(step: widget.firstItemStep!, child: tile);
          }
          return tile;
        },
      ),
    );
  }
}

/// 词汇列表项（单词 / 意群）
sealed class _VocabularyItem {
  DateTime get createdAt;
}

class _VocabularyWord extends _VocabularyItem {
  final SavedWord word;
  _VocabularyWord(this.word);
  @override
  DateTime get createdAt => word.createdAt;
}

class _VocabularyPhrase extends _VocabularyItem {
  final SavedSenseGroup phrase;
  _VocabularyPhrase(this.phrase);
  @override
  DateTime get createdAt => phrase.createdAt;
}

/// 收藏意群列表项（可展开，样式与 _SavedWordTile 一致）
class _SavedPhraseTile extends ConsumerStatefulWidget {
  final SavedSenseGroup savedPhrase;

  /// 仅词汇 tab 激活时预热，避免 IndexedStack 预建子树造成后台合成。
  final bool isActive;
  final bool isScrolling;

  /// 展开控制器（可选）：用于新手引导时由外部主动展开
  final ExpansibleController? expansionController;

  const _SavedPhraseTile({
    super.key,
    required this.savedPhrase,
    this.expansionController,
    required this.isActive,
    required this.isScrolling,
  });

  @override
  ConsumerState<_SavedPhraseTile> createState() => _SavedPhraseTileState();
}

class _SavedPhraseTileState extends ConsumerState<_SavedPhraseTile> {
  bool _isExpanded = false;
  String? _audioName;
  bool _hasSubmittedPrewarm = false;
  int _lastPrewarmConfigurationVersion = -1;

  @override
  void initState() {
    super.initState();
    _loadAudioName();
    _schedulePrewarm();
  }

  @override
  void didUpdateWidget(_SavedPhraseTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.isActive && !widget.isActive) ||
        (!oldWidget.isScrolling && widget.isScrolling)) {
      _hasSubmittedPrewarm = false;
    }
    if ((!oldWidget.isActive && widget.isActive) ||
        (oldWidget.isScrolling && !widget.isScrolling)) {
      _schedulePrewarm();
    }
  }

  /// Tile 被列表创建后才提交意群预热；增量接口负责跨 tile 去重与后台排队。
  void _schedulePrewarm() {
    final configurationVersion = ref.read(
      ttsControllerProvider.select((state) => state.configurationVersion),
    );
    if (!widget.isActive ||
        widget.isScrolling ||
        (_hasSubmittedPrewarm &&
            _lastPrewarmConfigurationVersion == configurationVersion)) {
      return;
    }
    _hasSubmittedPrewarm = true;
    _lastPrewarmConfigurationVersion = configurationVersion;
    final text = widget.savedPhrase.displayText;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isInScrollableViewport(context)) {
        ref.read(ttsControllerProvider.notifier).prewarmTextsIncremental([
          text,
        ]);
      }
    });
  }

  Future<void> _loadAudioName() async {
    final audioId = widget.savedPhrase.audioItemId;
    if (audioId == null) return;
    final dao = ref.read(audioItemDaoProvider);
    final row = await dao.getById(audioId);
    if (mounted && row != null) {
      setState(() => _audioName = row.name);
    }
  }

  /// 播放意群片段（优先意群时间，回退句子时间）
  Future<void> _playSentence() async {
    final phrase = widget.savedPhrase;
    AppLogger.log(
      'FavoritesPlayback',
      'source sentence tap phraseId=${phrase.id} text="${phrase.sentenceText}"',
    );
    final key = 'saved-phrase-source:${phrase.id}';
    final player = ref.read(shortAudioPlayerProvider);

    // 播放来源句子（非意群片段）
    if (player.state.playingKey == key) {
      await player.stop();
      return;
    }
    if (ref.read(ttsControllerProvider).speakingKey == key) {
      await ref.read(ttsControllerProvider.notifier).stop();
      return;
    }
    await _playSourceSentence(
      ref,
      key: key,
      audioItemId: phrase.audioItemId,
      sentenceIndex: phrase.sentenceIndex,
      sentenceText: phrase.sentenceText,
      sentenceStartMs: phrase.sentenceStartMs,
      sentenceEndMs: phrase.sentenceEndMs,
    );
    return;

    /* Legacy inline implementation retained temporarily during migration.
    try {
      final dao = ref.read(audioItemDaoProvider);
      final startMs = phrase.sentenceStartMs;
      final endMs = phrase.sentenceEndMs;
      final row = phrase.audioItemId == null
          ? null
          : await dao.getById(phrase.audioItemId!);
      final start = startMs;
      final end = endMs;

      if (row != null && start != null && end != null && mounted) {
        final audioItem = model.AudioItem(
          id: row.id,
          name: row.name,
          audioPath: row.audioPath,
          transcriptPath: row.transcriptPath,
          addedDate: row.addedDate,
          totalDuration: row.totalDuration,
          sentenceCount: row.sentenceCount,
          wordCount: row.wordCount,
          isPinned: row.isPinned,
          transcriptSource: model.TranscriptSource.fromIndex(
            row.transcriptSource,
          ),
          audioSha256: row.audioSha256,
          originalAudioSha256: row.originalAudioSha256,
          transcriptLanguage: row.transcriptLanguage,
        );

        final filePath = await audioItem.getFullAudioPath();
        if (mounted && filePath != null) {
          final played = await ref
              .read(shortAudioPlayerProvider)
              .playRangeFile(
                filePath,
                start: Duration(milliseconds: start),
                end: Duration(milliseconds: end),
              );
          if (played) return;
        }
      }

      if (row != null && phrase.sentenceText?.trim().isNotEmpty == true) {
        final srt = await dao.getTranscriptSrt(row.id);
        if (srt != null && srt.isNotEmpty) {
          final sentences = await SubtitleParser.parseSubtitleString(srt);
          var sentence =
              phrase.sentenceIndex != null &&
                  phrase.sentenceIndex! < sentences.length
              ? sentences[phrase.sentenceIndex!]
              : null;
          final storedText = phrase.sentenceText?.trim();
          if (storedText != null &&
              (sentence == null || sentence.text.trim() != storedText)) {
            sentence = null;
            for (final candidate in sentences) {
              if (candidate.text.trim() == storedText) {
                sentence = candidate;
                break;
              }
            }
          }
          if (sentence != null && mounted) {
            final audioItem = model.AudioItem(
              id: row.id,
              name: row.name,
              audioPath: row.audioPath,
              transcriptPath: row.transcriptPath,
              addedDate: row.addedDate,
              totalDuration: row.totalDuration,
              sentenceCount: row.sentenceCount,
              wordCount: row.wordCount,
              isPinned: row.isPinned,
              transcriptSource: model.TranscriptSource.fromIndex(
                row.transcriptSource,
              ),
              audioSha256: row.audioSha256,
              originalAudioSha256: row.originalAudioSha256,
              transcriptLanguage: row.transcriptLanguage,
            );
            final filePath = await audioItem.getFullAudioPath();
            if (filePath != null) {
              final played = await ref
                  .read(shortAudioPlayerProvider)
                  .playRangeFile(
                    filePath,
                    start: sentence.startTime,
                    end: sentence.endTime,
                  );
              if (played) return;
            }
          }
        }
      }

      final text = phrase.sentenceText;
      if (text != null && text.trim().isNotEmpty) {
        await ref.read(ttsControllerProvider.notifier).speak(text);
      }
    } catch (_) {
      // 忽略播放错误
    } finally {
      if (mounted) setState(() => _isPlaying = false);
    }
    */
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      ttsControllerProvider.select((state) => state.configurationVersion),
    );
    final playingKey = ref
        .watch(shortAudioPlaybackStateProvider)
        .valueOrNull
        ?.playingKey;
    final ttsPlayingKey = ref.watch(
      ttsControllerProvider.select((state) => state.speakingKey),
    );
    _schedulePrewarm();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final phrase = widget.savedPhrase;

    return Dismissible(
      key: ValueKey('phrase_${phrase.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.l),
        color: theme.colorScheme.error,
        child: Icon(Icons.bookmark_remove, color: theme.colorScheme.onError),
      ),
      onDismissed: (_) {
        ref
            .read(savedSenseGroupListProvider.notifier)
            .removeSenseGroup(phrase.phraseText);
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
          controller: widget.expansionController,
          childrenPadding: EdgeInsets.zero,
          iconColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          collapsedIconColor: theme.colorScheme.onSurfaceVariant.withValues(
            alpha: 0.4,
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          onExpansionChanged: (expanded) {
            setState(() => _isExpanded = expanded);
          },
          // 收起态仅预览一行来源句子，超长内容省略以保持列表紧凑。
          title: Text(
            phrase.displayText,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          subtitle: !_isExpanded && phrase.sentenceText != null
              ? Text(
                  phrase.sentenceText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
          // 展开状态：来源句子 + 来源音频
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.m,
                  AppSpacing.xs,
                  AppSpacing.m,
                  AppSpacing.m,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 意群同样属于收藏词汇：喇叭朗读收藏文本。
                    SpeakButton(
                      key: const Key('favorite_phrase_speak'),
                      text: phrase.displayText,
                      speakKey: 'favorite-phrase:${phrase.id}',
                      size: 18,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    // 来源句子（可播放）
                    if (phrase.sentenceText != null) ...[
                      InkWell(
                        onTap: _playSentence,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            if (phrase.sentenceText != null)
                              Icon(
                                playingKey ==
                                            'saved-phrase-source:${phrase.id}' ||
                                        ttsPlayingKey ==
                                            'saved-phrase-source:${phrase.id}'
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                                size: 18,
                                color:
                                    playingKey ==
                                            'saved-phrase-source:${phrase.id}' ||
                                        ttsPlayingKey ==
                                            'saved-phrase-source:${phrase.id}'
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            if (phrase.sentenceText != null)
                              const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                phrase.sentenceText!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 来源音频
                    if (_audioName != null && phrase.audioItemId != null) ...[
                      const SizedBox(height: AppSpacing.s),
                      GestureDetector(
                        onTap: () {
                          context.push(
                            AppRoutes.audioLearningPlan(phrase.audioItemId!),
                          );
                        },
                        child: _SourceAudioReference(
                          label: l10n.bookmarkReviewFromAudio(_audioName!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条收藏单词列表项（可展开）
class _SavedWordTile extends ConsumerStatefulWidget {
  final SavedWord savedWord;

  /// 仅词汇 tab 激活时预热，避免 IndexedStack 预建子树造成后台合成。
  final bool isActive;
  final bool isScrolling;

  /// 由父组件批量预加载的字典条目，避免每个 tile 独立异步查询
  final DictEntry? dictEntry;

  /// 展开控制器（可选）：用于新手引导时由外部主动展开
  final ExpansibleController? expansionController;

  const _SavedWordTile({
    super.key,
    required this.savedWord,
    this.dictEntry,
    this.expansionController,
    required this.isActive,
    required this.isScrolling,
  });

  @override
  ConsumerState<_SavedWordTile> createState() => _SavedWordTileState();
}

class _SavedWordTileState extends ConsumerState<_SavedWordTile> {
  bool _isExpanded = false;

  /// 源音频名称（异步加载）
  String? _audioName;
  bool _hasSubmittedPrewarm = false;
  int _lastPrewarmConfigurationVersion = -1;

  @override
  void initState() {
    super.initState();
    _loadAudioName();
    _schedulePrewarm();
  }

  @override
  void didUpdateWidget(_SavedWordTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.isActive && !widget.isActive) ||
        (!oldWidget.isScrolling && widget.isScrolling)) {
      _hasSubmittedPrewarm = false;
    }
    if ((!oldWidget.isActive && widget.isActive) ||
        (oldWidget.isScrolling && !widget.isScrolling)) {
      _schedulePrewarm();
    }
  }

  /// Tile 被列表创建后才预热；离线 Opus 命中时无需再生成同词的 TTS 缓存。
  void _schedulePrewarm() {
    final configurationVersion = ref.read(
      ttsControllerProvider.select((state) => state.configurationVersion),
    );
    if (!widget.isActive ||
        widget.isScrolling ||
        (_hasSubmittedPrewarm &&
            _lastPrewarmConfigurationVersion == configurationVersion)) {
      return;
    }
    _hasSubmittedPrewarm = true;
    _lastPrewarmConfigurationVersion = configurationVersion;
    final word = widget.savedWord.word;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isInScrollableViewport(context) ||
          ref.read(pronunciationClipsProvider(word)).isNotEmpty) {
        return;
      }
      ref.read(ttsControllerProvider.notifier).prewarmTextsIncremental([word]);
    });
  }

  /// 加载源音频名称
  Future<void> _loadAudioName() async {
    final audioId = widget.savedWord.audioItemId;
    if (audioId == null) return;
    final dao = ref.read(audioItemDaoProvider);
    final row = await dao.getById(audioId);
    if (mounted && row != null) {
      setState(() => _audioName = row.name);
    }
  }

  /// 播放来源句子的原声片段
  ///
  /// 优先使用冗余存储的 sentenceStartMs/sentenceEndMs（不依赖字幕文件），
  /// 仅在无时间信息时回退到加载字幕。
  Future<void> _playSentence() async {
    final word = widget.savedWord;
    final key = 'saved-word-source:${word.id}';
    final player = ref.read(shortAudioPlayerProvider);
    if (player.state.playingKey == key) {
      await player.stop();
      return;
    }
    if (ref.read(ttsControllerProvider).speakingKey == key) {
      await ref.read(ttsControllerProvider.notifier).stop();
      return;
    }
    await _playSourceSentence(
      ref,
      key: key,
      audioItemId: word.audioItemId,
      sentenceIndex: word.sentenceIndex,
      sentenceText: word.sentenceText,
      sentenceStartMs: word.sentenceStartMs,
      sentenceEndMs: word.sentenceEndMs,
    );
    return;

    /* Legacy inline implementation retained temporarily during migration.
    try {
      if (word.audioItemId == null) {
        if (word.sentenceText?.trim().isNotEmpty ?? false) {
          await ref
              .read(ttsControllerProvider.notifier)
              .speak(word.sentenceText!);
        }
        return;
      }

      // 从数据库获取音频项
      final dao = ref.read(audioItemDaoProvider);
      final row = await dao.getById(word.audioItemId!);
      if (row == null || !mounted) {
        if (word.sentenceText?.trim().isNotEmpty ?? false) {
          await ref
              .read(ttsControllerProvider.notifier)
              .speak(word.sentenceText!);
        }
        return;
      }

      final audioItem = model.AudioItem(
        id: row.id,
        name: row.name,
        audioPath: row.audioPath,
        transcriptPath: row.transcriptPath,
        addedDate: row.addedDate,
        totalDuration: row.totalDuration,
        sentenceCount: row.sentenceCount,
        wordCount: row.wordCount,
        isPinned: row.isPinned,
        transcriptSource: model.TranscriptSource.fromIndex(
          row.transcriptSource,
        ),
        audioSha256: row.audioSha256,
        originalAudioSha256: row.originalAudioSha256,
        transcriptLanguage: row.transcriptLanguage,
      );

      final filePath = await audioItem.getFullAudioPath();
      if (!mounted) return;
      if (filePath == null) {
        if (word.sentenceText?.trim().isNotEmpty ?? false) {
          await ref
              .read(ttsControllerProvider.notifier)
              .speak(word.sentenceText!);
        }
        return;
      }

      Duration startTime;
      Duration endTime;

      /// 存储时间是否可信（最少 200ms）
      const minDurationMs = 200;
      final storedDurationOk =
          hasStoredTiming &&
          (word.sentenceEndMs! - word.sentenceStartMs!) >= minDurationMs;

      if (hasStoredTiming && storedDurationOk) {
        // 使用冗余存储的时间（不依赖字幕文件）
        startTime = Duration(milliseconds: word.sentenceStartMs!);
        endTime = Duration(milliseconds: word.sentenceEndMs!);
      } else {
        // 回退：加载字幕获取句子时间信息
        final srt = await dao.getTranscriptSrt(word.audioItemId!);
        if (srt == null || srt.isEmpty) {
          if (word.sentenceText?.trim().isNotEmpty == true) {
            await ref
                .read(ttsControllerProvider.notifier)
                .speak(word.sentenceText!);
          }
          return;
        }
        final sentences = await SubtitleParser.parseSubtitleString(srt);
        if (!mounted || sentences.isEmpty) {
          if (word.sentenceText?.trim().isNotEmpty == true) {
            await ref
                .read(ttsControllerProvider.notifier)
                .speak(word.sentenceText!);
          }
          return;
        }

        // 优先用 sentenceIndex，但若字幕重新生成导致索引错位，
        // 则通过 sentenceText 匹配找到正确句子
        final idx = word.sentenceIndex;
        var sentence = idx != null && idx < sentences.length
            ? sentences[idx]
            : null;
        final storedText = word.sentenceText;

        if (storedText != null &&
            (sentence == null || sentence.text.trim() != storedText.trim())) {
          sentence = null;
          for (final s in sentences) {
            if (s.text.trim() == storedText.trim()) {
              sentence = s;
              break;
            }
          }
        }

        if (sentence == null) {
          if (word.sentenceText?.trim().isNotEmpty == true) {
            await ref
                .read(ttsControllerProvider.notifier)
                .speak(word.sentenceText!);
          }
          return;
        }
        startTime = sentence.startTime;
        endTime = sentence.endTime;
      }

      final played = await ref
          .read(shortAudioPlayerProvider)
          .playRangeFile(filePath, start: startTime, end: endTime);
      if (!played && word.sentenceText?.trim().isNotEmpty == true) {
        await ref
            .read(ttsControllerProvider.notifier)
            .speak(word.sentenceText!);
      }
    } catch (_) {
      // 忽略播放错误（音频文件不存在等）
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
    */
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      ttsControllerProvider.select((state) => state.configurationVersion),
    );
    final playingKey = ref
        .watch(shortAudioPlaybackStateProvider)
        .valueOrNull
        ?.playingKey;
    final ttsPlayingKey = ref.watch(
      ttsControllerProvider.select((state) => state.speakingKey),
    );
    _schedulePrewarm();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final word = widget.savedWord;
    final previewText = _collapsedPreviewText(word, widget.dictEntry);
    return Dismissible(
      key: ValueKey('word_${word.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.l),
        color: theme.colorScheme.error,
        child: Icon(Icons.bookmark_remove, color: theme.colorScheme.onError),
      ),
      onDismissed: (_) {
        ref.read(savedWordListProvider.notifier).removeWord(word.word);
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
          controller: widget.expansionController,
          childrenPadding: EdgeInsets.zero,
          iconColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          collapsedIconColor: theme.colorScheme.onSurfaceVariant.withValues(
            alpha: 0.4,
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          onExpansionChanged: (expanded) {
            setState(() => _isExpanded = expanded);
          },
          // 收起状态：单词 + 收藏图标 + 音标 + 简释
          title: Text(
            word.word,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          subtitle: !_isExpanded && previewText != null
              ? Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
          // 展开状态：完整释义（仅多行时）+ 柯林斯星级 + 考试标签 + 来源句子
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.m,
                  AppSpacing.xs,
                  AppSpacing.m,
                  AppSpacing.m,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 播放入口不依赖本地词典命中，固定跟随音标左侧排列。
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.dictEntry?.phonetic.isNotEmpty ?? false)
                          Flexible(
                            child: Text(
                              '/${widget.dictEntry!.phonetic}/',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (widget.dictEntry?.phonetic.isNotEmpty ?? false)
                          const SizedBox(width: AppSpacing.xs),
                        SpeakButton(
                          key: const Key('favorite_speak'),
                          text: word.word,
                          size: 18,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    // 完整释义仅在本地词典精确命中时展示。
                    if (widget.dictEntry != null) ...[
                      if (widget.dictEntry!.translation != null) ...[
                        const SizedBox(height: AppSpacing.s),
                        Text(
                          widget.dictEntry!.translation!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.6,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ],

                    // 柯林斯星级 + 考试标签
                    if (widget.dictEntry != null &&
                        (widget.dictEntry!.collins > 0 ||
                            widget.dictEntry!.examTags.isNotEmpty)) ...[
                      const SizedBox(height: AppSpacing.s),
                      _buildMetaTags(theme, widget.dictEntry!),
                    ],

                    // 来源句子
                    if (word.sentenceText != null) ...[
                      const SizedBox(height: AppSpacing.m),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      InkWell(
                        onTap: _playSentence,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            if (word.sentenceText != null)
                              Icon(
                                playingKey == 'saved-word-source:${word.id}' ||
                                        ttsPlayingKey ==
                                            'saved-word-source:${word.id}'
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                                size: 18,
                                color:
                                    playingKey ==
                                            'saved-word-source:${word.id}' ||
                                        ttsPlayingKey ==
                                            'saved-word-source:${word.id}'
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            if (word.sentenceText != null)
                              const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                word.sentenceText!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 源音频引用
                    if (_audioName != null && word.audioItemId != null) ...[
                      const SizedBox(height: AppSpacing.s),
                      GestureDetector(
                        onTap: () {
                          context.push(
                            AppRoutes.audioLearningPlan(word.audioItemId!),
                          );
                        },
                        child: _SourceAudioReference(
                          label: l10n.bookmarkReviewFromAudio(_audioName!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 简短副标题：音标 + 首行释义
  String _buildSubtitle(DictEntry entry) {
    final parts = <String>[];
    if (entry.phonetic.isNotEmpty) {
      parts.add('/${entry.phonetic}/');
    }
    if (entry.translation != null && entry.translation!.isNotEmpty) {
      final firstLine = entry.translation!.split('\n').first.trim();
      parts.add(firstLine);
    }
    return parts.join(' ');
  }

  /// 多词收藏优先预览来源句子，单词继续展示词典摘要。
  String? _collapsedPreviewText(SavedWord word, DictEntry? dictEntry) {
    final hasMultipleWords = word.word.trim().contains(RegExp(r'\s'));
    if (hasMultipleWords && (word.sentenceText?.isNotEmpty ?? false)) {
      return word.sentenceText;
    }
    if (dictEntry == null) return null;
    return _buildSubtitle(dictEntry);
  }

  /// 柯林斯星级 + 考试标签 Wrap
  Widget _buildMetaTags(ThemeData theme, DictEntry entry) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (entry.collins > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (i) {
              return Icon(
                Icons.star_rounded,
                size: 12,
                color: i < entry.collins
                    ? Colors.amber.shade600
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              );
            }),
          ),
        for (final tag in entry.examTags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// 来源音频固定为单行左对齐，保证窄屏和超长标题下仍保留跳转入口。
class _SourceAudioReference extends StatelessWidget {
  final String label;

  const _SourceAudioReference({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.outline.withValues(alpha: 0.7);
    return Row(
      children: [
        Icon(Icons.headphones, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 共用空状态
// ============================================================

Widget _buildEmptyState(BuildContext context, {required bool isSentences}) {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);

  return Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSentences ? Icons.format_quote : Icons.abc,
            size: 56,
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            isSentences
                ? l10n.favoritesNoSentences
                : l10n.favoritesNoVocabulary,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            isSentences
                ? l10n.favoritesNoSentencesHint
                : l10n.favoritesNoVocabularyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    ),
  );
}
