/// Flashcard 卡片组件
///
/// 包含 3D 翻转动画（Matrix4.rotateY），正面显示单词+音标+发音，
/// 背面显示释义+来源例句。底部收藏切换按钮。
///
/// 纯展示层，所有状态从 [FlashcardNotifier] 读取，
/// 用户操作通过调用 Notifier 方法触发。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../database/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../models/dict_entry.dart';
import '../../models/flashcard_item.dart';
import '../../providers/flashcard/flashcard_flow_phase.dart';
import '../../providers/flashcard/flashcard_provider.dart';
import '../../router/app_router.dart';
import '../../theme/app_theme.dart';
import '../common/text_context_menu.dart';

/// Flashcard 翻转卡片
class FlashcardCard extends StatefulWidget {
  /// 翻转动画时长
  static const flipDuration = Duration(milliseconds: 400);

  /// 卡片数据
  final FlashcardItem item;

  /// 是否显示背面
  final bool isShowingBack;

  /// 翻转回调
  final VoidCallback onFlip;

  /// 切换收藏状态回调
  final VoidCallback onUnsave;

  /// 当前单词是否已取消收藏
  final bool isUnsaved;

  const FlashcardCard({
    super.key,
    required this.item,
    required this.isShowingBack,
    required this.onFlip,
    required this.onUnsave,
    this.isUnsaved = false,
  });

  @override
  State<FlashcardCard> createState() => _FlashcardCardState();
}

class _FlashcardCardState extends State<FlashcardCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFrontContent = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FlashcardCard.flipDuration,
    );
    _animation = Tween<double>(
      begin: 0,
      end: math.pi,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 在动画 50% 处切换正/背面内容
    _controller.addListener(() {
      final shouldShowFront = _controller.value < 0.5;
      if (_showFrontContent != shouldShowFront) {
        setState(() => _showFrontContent = shouldShowFront);
      }
    });

    if (widget.isShowingBack) {
      _controller.value = 1.0;
      _showFrontContent = false;
    } else {
      _showFrontContent = true;
    }
  }

  @override
  void didUpdateWidget(covariant FlashcardCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 检测卡片切换（不同单词）→ 立即重置无动画
    if (oldWidget.item.displayText != widget.item.displayText) {
      _controller.value = widget.isShowingBack ? 1.0 : 0.0;
      _showFrontContent = !widget.isShowingBack;
      return;
    }

    // 翻转动画
    if (widget.isShowingBack != oldWidget.isShowingBack) {
      if (widget.isShowingBack) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onFlip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          // 背面内容需要水平镜像翻转，否则文字是反的
          final angle = _animation.value;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001) // 透视效果
            ..rotateY(angle);

          return Transform(
            alignment: Alignment.center,
            transform: transform,
            child: _showFrontContent
                ? _FrontContent(
                    item: widget.item,
                    onUnsave: widget.onUnsave,
                    isUnsaved: widget.isUnsaved,
                  )
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _BackContent(
                      item: widget.item,
                      onUnsave: widget.onUnsave,
                      isUnsaved: widget.isUnsaved,
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// 正面内容：单词 + 音标 + 发音 + 柯林斯星级
class _FrontContent extends StatelessWidget {
  final FlashcardItem item;
  final VoidCallback onUnsave;
  final bool isUnsaved;

  const _FrontContent({
    required this.item,
    required this.onUnsave,
    this.isUnsaved = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = item;
    final dict = item.dictEntry;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),

            // 柯林斯星级（角落淡显）
            if (dict != null && dict.collins > 0) ...[
              _CollinsStars(rating: dict.collins),
              const SizedBox(height: AppSpacing.m),
            ],

            // 单词（大号居中，支持长按/右键复制）
            GestureDetector(
              onLongPressStart: (details) => TextContextMenu.show(
                context,
                details.globalPosition,
                word.displayText,
              ),
              onSecondaryTapDown: (details) => TextContextMenu.show(
                context,
                details.globalPosition,
                word.displayText,
              ),
              child: Text(
                word.displayText,
                style: _displayTextStyle(theme, word.displayText.length),
                textAlign: TextAlign.center,
              ),
            ),

            // 音标
            if (dict != null && dict.phonetic.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                '/${dict.phonetic}/',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // 发音按钮 — 调用 notifier.userPlayWord()
            const SizedBox(height: AppSpacing.m),
            Consumer(
              builder: (context, ref, _) {
                return IconButton.filled(
                  onPressed: () => ref
                      .read(flashcardNotifierProvider.notifier)
                      .userPlayWord(),
                  icon: const Icon(Icons.volume_up),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    foregroundColor: theme.colorScheme.primary,
                  ),
                );
              },
            ),

            const Spacer(),

            // 收藏切换按钮
            _SaveToggleButton(onTap: onUnsave, isUnsaved: isUnsaved),

            const SizedBox(height: AppSpacing.m),
          ],
        ),
      ),
    );
  }
}

/// 背面内容：单词+音标(小) + 柯林斯+标签 + 词性+释义 + 来源例句（可播放）
class _BackContent extends ConsumerStatefulWidget {
  final FlashcardItem item;
  final VoidCallback onUnsave;
  final bool isUnsaved;

  const _BackContent({
    required this.item,
    required this.onUnsave,
    this.isUnsaved = false,
  });

  @override
  ConsumerState<_BackContent> createState() => _BackContentState();
}

class _BackContentState extends ConsumerState<_BackContent> {
  /// 源音频名称（异步加载）
  String? _audioName;

  @override
  void initState() {
    super.initState();
    _loadAudioName();
  }

  /// 加载源音频名称
  Future<void> _loadAudioName() async {
    final audioId = widget.item.audioItemId;
    if (audioId == null) return;
    final dao = ref.read(audioItemDaoProvider);
    final row = await dao.getById(audioId);
    if (mounted && row != null) {
      setState(() => _audioName = row.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = widget.item;
    final dict = widget.item.dictEntry;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          children: [
            // 主体内容整体居中（单词+释义+例句作为一个块）
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 单词/意群文本
                      GestureDetector(
                        onLongPressStart: (details) => TextContextMenu.show(
                          context,
                          details.globalPosition,
                          word.displayText,
                        ),
                        onSecondaryTapDown: (details) => TextContextMenu.show(
                          context,
                          details.globalPosition,
                          word.displayText,
                        ),
                        child: Text(
                          word.displayText,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // 音标 + TTS
                      Row(
                        children: [
                          if (dict != null && dict.phonetic.isNotEmpty)
                            Text(
                              '/${dict.phonetic}/',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (dict != null && dict.phonetic.isNotEmpty)
                            const SizedBox(width: AppSpacing.xs),
                          Consumer(
                            builder: (context, ref, _) {
                              return SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  onPressed: () => ref
                                      .read(flashcardNotifierProvider.notifier)
                                      .userPlayWord(),
                                  icon: const Icon(Icons.volume_up, size: 18),
                                  color: theme.colorScheme.primary,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      // 柯林斯星级 + 考试标签
                      if (dict != null &&
                          (dict.collins > 0 || dict.examTags.isNotEmpty)) ...[
                        const SizedBox(height: AppSpacing.s),
                        _buildMetaTags(theme, dict),
                      ],

                      const SizedBox(height: AppSpacing.m),

                      // 释义
                      if (dict != null && dict.translation != null)
                        _buildTranslation(theme, dict.translation!),

                      // 来源例句
                      if (word.sentenceText != null) ...[
                        const SizedBox(height: AppSpacing.m),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.m),
                        _SentenceRow(item: word),
                      ],

                      // 源音频引用
                      if (_audioName != null && word.audioItemId != null) ...[
                        const SizedBox(height: AppSpacing.s),
                        _AudioSourceLink(
                          audioName: _audioName!,
                          audioItemId: word.audioItemId!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // 收藏切换按钮
            const SizedBox(height: AppSpacing.m),
            _SaveToggleButton(
              onTap: widget.onUnsave,
              isUnsaved: widget.isUnsaved,
            ),
          ],
        ),
      ),
    );
  }

  /// 释义内容 — 解析词性前缀
  Widget _buildTranslation(ThemeData theme, String translation) {
    final lines = translation.split('\n').where((l) => l.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _buildDefinitionLine(theme, line.trim()),
          ),
      ],
    );
  }

  /// 单条释义行 — 词性标签 + 释义文本
  Widget _buildDefinitionLine(ThemeData theme, String line) {
    final posMatch = RegExp(
      r'^([a-z]+\.(?:\s*&\s*[a-z]+\.)*)\s*',
    ).firstMatch(line);

    if (posMatch == null) {
      return Text(
        line,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      );
    }

    final pos = posMatch.group(1)!;
    final definition = line.substring(posMatch.end);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              pos,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
                height: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            definition,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        ),
      ],
    );
  }

  /// 柯林斯星级 + 考试标签
  Widget _buildMetaTags(ThemeData theme, DictEntry entry) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (entry.collins > 0) _CollinsStars(rating: entry.collins),
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

/// 来源例句行 — 点击整行播放句子原声
///
/// 从 provider 读取 isSentencePlaying 控制播放/停止图标。
class _SentenceRow extends ConsumerWidget {
  final FlashcardItem item;

  const _SentenceRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final canPlay =
        item.audioItemId != null &&
        (item.sentenceIndex != null ||
            (item.sentenceStartMs != null && item.sentenceEndMs != null));

    // 从 provider 读取播放状态（自动播放用 phase，手动播放用 isSentencePlaying）
    final isPlaying = ref.watch(
      flashcardNotifierProvider.select(
        (s) => s.isSentencePlaying || s.phase is FlashcardPlayingSentence,
      ),
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPlay)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              isPlaying
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
              size: 22,
              color: isPlaying
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
        Expanded(
          child: Text(
            item.sentenceText!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      ],
    );

    // 可播放时，整行点击触发播放
    // onTapDown 确保在手势竞技场中胜出，阻止外层 onTap（翻转）触发
    if (canPlay) {
      return GestureDetector(
        onTapDown: (_) {},
        onTap: () =>
            ref.read(flashcardNotifierProvider.notifier).userPlaySentence(),
        onLongPressStart: (details) => TextContextMenu.show(
          context,
          details.globalPosition,
          item.sentenceText!,
        ),
        onSecondaryTapDown: (details) => TextContextMenu.show(
          context,
          details.globalPosition,
          item.sentenceText!,
        ),
        behavior: HitTestBehavior.opaque,
        child: row,
      );
    }
    // 不可播放时也支持长按/右键复制
    return GestureDetector(
      onLongPressStart: (details) => TextContextMenu.show(
        context,
        details.globalPosition,
        item.sentenceText!,
      ),
      onSecondaryTapDown: (details) => TextContextMenu.show(
        context,
        details.globalPosition,
        item.sentenceText!,
      ),
      child: row,
    );
  }
}

/// 收藏状态切换按钮（正面/背面共享）
class _SaveToggleButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isUnsaved;

  const _SaveToggleButton({required this.onTap, this.isUnsaved = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.s,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUnsaved ? Icons.bookmark_border : Icons.bookmark,
                size: 20,
                color: isUnsaved
                    ? theme.colorScheme.outline
                    : AppTheme.bookmarkColor,
              ),
              const SizedBox(width: 6),
              Text(
                isUnsaved
                    ? l10n.favoritesVocabularyRemoved
                    : l10n.flashcardUnsaveHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 源音频引用链接（小字弱化，右对齐，点击跳转学习计划）
class _AudioSourceLink extends StatelessWidget {
  final String audioName;
  final String audioItemId;

  const _AudioSourceLink({required this.audioName, required this.audioItemId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.audioLearningPlan(audioItemId)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headphones,
              size: 12,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                l10n.bookmarkReviewFromAudio(audioName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.outline.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 柯林斯星级
/// 根据文本长度计算闪卡正面的字体样式
///
/// 短单词用大号字体，长意群/短语逐级缩小，保证可读性。
TextStyle? _displayTextStyle(ThemeData theme, int length) {
  final TextStyle? base;
  if (length <= 10) {
    base = theme.textTheme.displaySmall; // ~36sp
  } else if (length <= 20) {
    base = theme.textTheme.headlineLarge; // ~32sp
  } else if (length <= 35) {
    base = theme.textTheme.headlineMedium; // ~28sp
  } else if (length <= 50) {
    base = theme.textTheme.headlineSmall; // ~24sp
  } else {
    base = theme.textTheme.titleLarge; // ~22sp
  }
  return base?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5);
}

class _CollinsStars extends StatelessWidget {
  final int rating;

  const _CollinsStars({required this.rating});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          Icons.star_rounded,
          size: 14,
          color: i < rating
              ? Colors.amber.shade600
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        );
      }),
    );
  }
}
