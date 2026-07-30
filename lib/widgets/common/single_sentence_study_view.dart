import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/audio_item.dart';
import '../../models/sentence.dart';
import '../../providers/sentence_ai_provider.dart';
import '../../services/subtitle_parser.dart';
import '../../theme/app_theme.dart';
import '../dictionary/dictionary_panel_host.dart';
import '../practice/annotation_content_view.dart';
import 'bookmark_toggle_row.dart';

const kFullSingleSentenceSwipeAreaKey = ValueKey(
  'player-single-sentence-swipe-area',
);
const kBookmarkSingleSentenceSwipeAreaKey = ValueKey(
  'player-bookmark-single-sentence-swipe-area',
);

/// 单句视图所在的播放列表，用于隔离全文与收藏两个分页器。
enum SingleSentenceStudyScope { full, bookmarks }

/// 单句视图触发的播放器动作。
///
/// 组件只表达交互意图，不依赖 just_audio 或 media_kit 的 controller。
class SingleSentenceStudyActions {
  const SingleSentenceStudyActions({
    required this.onSentenceSelected,
    required this.onBookmarkToggle,
    required this.onStopMainPlayer,
    required this.onToolbarButtonTapped,
  });

  final Future<void> Function(int index, {bool autoPlay}) onSentenceSelected;
  final ValueChanged<int> onBookmarkToggle;
  final VoidCallback onStopMainPlayer;
  final VoidCallback onToolbarButtonTapped;
}

/// 音频与视频随心听共用的单句精听视图。
///
/// 负责句子元信息、难句标记、讲解内容和左右分页；播放状态仍由调用页面对应的
/// controller 管理。程序化分页期间会屏蔽回调，避免自动推进或循环回卷反向重启播放。
class SingleSentenceStudyView extends ConsumerStatefulWidget {
  const SingleSentenceStudyView({
    super.key,
    required this.audioItem,
    required this.sentences,
    required this.currentSentenceIndex,
    required this.bookmarkedSentenceIndices,
    required this.showTranscript,
    required this.isPlaying,
    required this.scope,
    required this.actions,
  });

  final AudioItem audioItem;
  final List<Sentence> sentences;
  final int currentSentenceIndex;
  final Set<int> bookmarkedSentenceIndices;
  final bool showTranscript;
  final bool isPlaying;
  final SingleSentenceStudyScope scope;
  final SingleSentenceStudyActions actions;

  @override
  ConsumerState<SingleSentenceStudyView> createState() =>
      _SingleSentenceStudyViewState();
}

class _SingleSentenceStudyViewState
    extends ConsumerState<SingleSentenceStudyView> {
  final PageController _pageController = PageController();
  bool _pagerSynced = false;
  bool _programmaticPageChange = false;

  /// 切句即结束查词会话（本视图由播放器真相源的 [currentSentenceIndex] 驱动，
  /// 横滑 / 自动推进 / 进度条跳句 / 底部切句最终都收敛到这里，是单一入口）。
  ///
  /// 面板与选区绑定在同一个句子上：`PageView` 每页是独立实例，跨句存活会让
  /// 已离屏的旧 owner 继续把焦点和操作条投影到离屏页的几何上。
  @override
  void didUpdateWidget(SingleSentenceStudyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSentenceIndex != widget.currentSentenceIndex) {
      DictionaryPanelHost.maybeOf(context)?.closeIfOpen();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetPosition = widget.sentences.indexWhere(
      (sentence) => sentence.index == widget.currentSentenceIndex,
    );
    if (targetPosition < 0) return const SizedBox.shrink();

    _syncPage(targetPosition);

    return PageView.builder(
      key: widget.scope == SingleSentenceStudyScope.bookmarks
          ? kBookmarkSingleSentenceSwipeAreaKey
          : kFullSingleSentenceSwipeAreaKey,
      // 面板开着时不接受滑动：屏障按区域放行正文文本以支持连续点词，而触屏的
      // 水平拖拽不被文本消费，会穿到这里造成「切句了但面板还开着」。
      // 文本区域的 tap / 长按 / 手柄拖拽不受影响。
      physics: DictionaryPanelHost.isPanelOpenOf(context)
          ? const NeverScrollableScrollPhysics()
          : null,
      controller: _pageController,
      itemCount: widget.sentences.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, position) => _buildSentencePage(
        widget.sentences[position],
        isActivePage: position == targetPosition,
      ),
    );
  }

  Widget _buildSentenceHeader(Sentence sentence) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.m,
        AppSpacing.m,
        AppSpacing.m,
      ),
      child: Row(
        children: [
          Text('#${sentence.index + 1}', style: AppTextStyles.caption(context)),
          const SizedBox(width: AppSpacing.l),
          Text(
            '${SubtitleParser.formatDuration(sentence.startTime)} - '
            '${SubtitleParser.formatDuration(sentence.endTime)}',
            style: AppTextStyles.caption(context),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: BookmarkToggleRow(
              isDifficult: widget.bookmarkedSentenceIndices.contains(
                sentence.index,
              ),
              onTap: () => widget.actions.onBookmarkToggle(sentence.index),
            ),
          ),
        ],
      ),
    );
  }

  /// 将播放器真相源同步到分页器；相邻句动画过渡，跨多句直接跳转。
  void _syncPage(int targetPosition) {
    final firstSync = !_pagerSynced;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      if (_pageController.page?.round() == targetPosition) return;

      _programmaticPageChange = true;
      final currentPage = _pageController.page?.round();
      final isAdjacent =
          !firstSync &&
          currentPage != null &&
          (targetPosition - currentPage).abs() == 1;
      if (isAdjacent) {
        _pageController
            .animateToPage(
              targetPosition,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _programmaticPageChange = false);
      } else {
        _pageController.jumpToPage(targetPosition);
        _programmaticPageChange = false;
      }
    });
    _pagerSynced = true;
  }

  /// 用户翻页时把列表位置映射回全局句子索引，并保持当前播放/暂停状态。
  void _onPageChanged(int position) {
    if (_programmaticPageChange ||
        position < 0 ||
        position >= widget.sentences.length) {
      return;
    }
    final index = widget.sentences[position].index;
    if (index == widget.currentSentenceIndex) return;
    unawaited(
      widget.actions.onSentenceSelected(index, autoPlay: widget.isPlaying),
    );
  }

  Widget _buildSentencePage(Sentence sentence, {required bool isActivePage}) {
    return Stack(
      children: [
        AnnotationContentView(
          key: ValueKey(sentence.index),
          text: sentence.text,
          aiNotifier: ref.read(sentenceAiNotifierProvider),
          audioItemId: widget.audioItem.id,
          sentenceIndex: sentence.index,
          sentenceStartMs: sentence.startTime.inMilliseconds,
          sentenceEndMs: sentence.endTime.inMilliseconds,
          onStopMainPlayer: widget.actions.onStopMainPlayer,
          onToolbarButtonTapped: widget.actions.onToolbarButtonTapped,
          enableGuide: isActivePage,
          toolbarPlacement: AnnotationToolbarPlacement.scrollWithContent,
          scrollHeader: _buildSentenceHeader(sentence),
          // 单句分页器满宽；工具栏、原文和译文各自留出稳定内边距，
          // 解析内容面板则使用整行宽度与其自身的内容内边距。
          contentHorizontalPadding: AppSpacing.m,
        ),
        if (!widget.showTranscript)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.05),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
