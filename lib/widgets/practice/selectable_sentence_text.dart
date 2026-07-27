/// 可点词 + 系统标准选区的句子文本组件（统一标注卡与盲听偷看两套点词实现）
///
/// - 点单词：用系统选区选中该词并立即查询；
/// - 长按：由 Flutter 建立平台默认选区并显示系统手柄；
/// - 拖动手柄：保持系统标准字符级选区，松手后查询最终选中文本。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chatbot/chatbot_flags.dart';
import '../../features/chatbot/widgets/selection_toolbar.dart';
import '../../features/chatbot/widgets/sentence_chat_button.dart';
import '../../features/remote_config/remote_config.dart';
import '../../features/remote_config/remote_config_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../models/speech_practice_models.dart';
import '../../providers/saved_word_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/saved_text_index.dart';
import '../../utils/text_normalize.dart';
import '../common/platform_selection_feedback.dart';
import '../common/platform_text_selection_style.dart';
import '../dictionary/dictionary_panel_host.dart';
import 'sentence_word_selection.dart';

/// 查词来源上下文（收藏溯源用），聚合原先散落的 5 个参数
class DictionaryLookupOrigin {
  /// 来源音频 ID（可选）
  final String? audioItemId;

  /// 来源句子索引（可选）
  final int? sentenceIndex;

  /// 来源句子文本
  final String? sentenceText;

  /// 来源句子起始时间（毫秒，可选）
  final int? sentenceStartMs;

  /// 来源句子结束时间（毫秒，可选）
  final int? sentenceEndMs;

  const DictionaryLookupOrigin({
    this.audioItemId,
    this.sentenceIndex,
    this.sentenceText,
    this.sentenceStartMs,
    this.sentenceEndMs,
  });

  /// 组装词典面板查询
  DictionaryPanelQuery queryFor(String word) => DictionaryPanelQuery(
    word: word,
    audioItemId: audioItemId,
    sentenceIndex: sentenceIndex,
    sentenceText: sentenceText,
    sentenceStartMs: sentenceStartMs,
    sentenceEndMs: sentenceEndMs,
  );
}

/// 可点词句子文本
///
/// 已收藏的单词/词组/意群渲染橙色点状下划线标记（低干扰，与选区背景、
/// 跟读评分文字色正交可叠加）。收藏集合经 Riverpod 流式监听，
/// 收藏/取消收藏时所有可见句子即时刷新。
class SelectableSentenceText extends ConsumerStatefulWidget {
  /// 句子文本（无 [highlightedSegments] 时的渲染与分词来源）
  final String text;

  /// 文本样式
  final TextStyle? style;

  /// 高亮片段（跟读评分染色）；非空时渲染文本 = 片段拼接
  final List<SpeechTranscriptSegment>? highlightedSegments;

  /// 查词来源上下文（收藏溯源）
  final DictionaryLookupOrigin origin;

  /// 查词前副作用钩子（盲听进入等待用户态、标注卡切手动模式等）。
  /// 点词与词组松手时、面板 show 之前触发。
  final VoidCallback? onBeforeLookup;

  const SelectableSentenceText({
    super.key,
    required this.text,
    this.style,
    this.highlightedSegments,
    this.origin = const DictionaryLookupOrigin(),
    this.onBeforeLookup,
  });

  @override
  ConsumerState<SelectableSentenceText> createState() =>
      _SelectableSentenceTextState();
}

class _SelectableSentenceTextState
    extends ConsumerState<SelectableSentenceText> {
  /// 系统可选文本的 key，用于保留点词时的精确命中判断。
  final GlobalKey _textKey = GlobalKey();

  /// 系统选区焦点；面板关闭或其它句子发起查词时用于清除旧选区。
  final FocusNode _focusNode = FocusNode();

  /// 分词结果（text/segments 变化时重建）
  late List<WordToken> _tokens = tokenizeSentence(_fullText);

  /// Flutter 当前选区；长按/拖动期间只记录，直到手指松开才触发查词。
  TextSelection? _currentSelection;
  bool _selectionLookupPending = false;
  bool _selectionCommitScheduled = false;

  /// 最近一次按下位置，仅用于区分正文字符与行尾空白的单击。
  Offset? _lastPointerDownPosition;

  /// Flutter 在 iOS 首次未聚焦长按时不发送平台反馈；记录起手焦点以便补齐。
  bool _hadFocusOnPointerDown = false;
  bool _longPressFeedbackCompleted = false;

  /// 已注册豁免区域的宿主（组件卸载时按同一实例注销）
  DictionaryPanelHostState? _host;

  /// 收藏标记掩码缓存（(文本, 索引实例) 不变时复用，避免每帧重算；
  /// 索引是 keepAlive provider 缓存的同一对象，identical 判等即可）
  List<bool> _savedMask = const [];
  String? _savedMaskText;
  SavedTextIndex? _savedMaskIndex;

  /// 当前词汇收藏 key；操作条按它判断选区应显示“收藏”还是“取消收藏”。
  Set<String> _savedWordTexts = const {};

  /// 操作条收藏按钮的乐观状态；数据库流追上后自动移除对应覆盖。
  final Map<String, bool> _pendingSavedWordStates = {};

  /// 渲染文本：有高亮片段时为片段拼接，否则为原句
  String get _fullText {
    final segs = widget.highlightedSegments;
    if (segs == null || segs.isEmpty) return widget.text;
    return segs.map((s) => s.text).join();
  }

  EditableTextState? get _editableState {
    final root = _textKey.currentContext;
    EditableTextState? result;
    void findEditableState(Element child) {
      if (result != null) return;
      if (child is StatefulElement) {
        final state = child.state;
        if (state is EditableTextState) {
          result = state;
          return;
        }
      }
      child.visitChildElements(findEditableState);
    }

    root?.visitChildElements(findEditableState);
    return result;
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    // 系统选择手柄位于 Overlay，组件自身 Listener 收不到手柄松开事件，
    // 因此只监听全局 pointer up/cancel 来提交已经由 Flutter 产生的选区。
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
  }

  @override
  void didUpdateWidget(SelectableSentenceText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换句时清除旧选区并重新分词。
    final oldFull = oldWidget.highlightedSegments?.map((s) => s.text).join();
    final oldText = (oldFull == null || oldFull.isEmpty)
        ? oldWidget.text
        : oldFull;
    if (oldText != _fullText) {
      _tokens = tokenizeSentence(_fullText);
      _currentSelection = null;
      _selectionLookupPending = false;
      _focusNode.unfocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 面板打开时，正文区域仍可继续单击或长按查词。
    final host = DictionaryPanelHost.maybeOf(context);
    if (!identical(host, _host)) {
      _host?.unregisterTapThroughHitTest(_hitsTapThrough);
      _host = host;
      _host?.registerTapThroughHitTest(_hitsTapThrough);
    }
    // 面板关闭或其它组件发起查词时，清除当前系统选区。
    final owner = DictionaryPanelHost.activeOwnerOf(context);
    if (_focusNode.hasFocus && !identical(owner, this)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.hasFocus) _focusNode.unfocus();
      });
    }
  }

  @override
  void dispose() {
    _host?.unregisterTapThroughHitTest(_hitsTapThrough);
    _focusNode.removeListener(_handleFocusChanged);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _focusNode.dispose();
    super.dispose();
  }

  /// 屏障仅放行正文 bounds；系统手柄自身位于 Overlay，不需要自定义命中区。
  bool _hitsTapThrough(Offset globalPosition) {
    final obj = context.findRenderObject();
    if (obj is! RenderBox || !obj.attached || !obj.hasSize) return false;
    final local = obj.globalToLocal(globalPosition);
    return (Offset.zero & obj.size).contains(local);
  }

  // -- 查词触发 --

  void _lookup(String text) {
    widget.onBeforeLookup?.call();
    DictionaryPanelHost.of(
      context,
    ).show(widget.origin.queryFor(text), owner: this);
  }

  /// 选区因点击其它区域或路由切换而失焦时，只关闭本组件发起的词典面板。
  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _closeOwnedDictionary();
  }

  void _closeOwnedDictionary() {
    _host?.closeIfOwnedBy(this);
  }

  /// 保留原有单击查词；系统单击形成的折叠选区提供字符位置。
  void _handleTap() {
    final editableState = _editableState;
    final editable = editableState?.renderEditable;
    final globalPosition = _lastPointerDownPosition;
    if (editable == null || globalPosition == null || _tokens.isEmpty) return;
    final pos = editable.getPositionForPoint(globalPosition);
    // 光标位可能落在词右边界（== end），前移一位再判定
    var idx = wordTokenAtChar(_tokens, pos.offset);
    if (idx < 0 && pos.offset > 0) {
      idx = wordTokenAtChar(_tokens, pos.offset - 1);
    }
    if (idx < 0) return;
    // 防止行尾空白区域反查到最近词而误触发。
    final t = _tokens[idx];
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: t.start, extentOffset: t.end),
    );
    final localPosition = editable.globalToLocal(globalPosition);
    final hit = boxes.any((b) => b.toRect().inflate(2).contains(localPosition));
    if (!hit) return;
    // 复用 RenderEditable 的系统分词边界与平台手柄，不自行绘制或维护选区。
    editable.selectWord(cause: SelectionChangedCause.tap);
    editableState?.showToolbar();
    _lookup(t.text);
  }

  /// 选择变化时只保存状态；真正查词由 pointer up 统一提交。
  void _handleSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    _currentSelection = selection;
    if (!selection.isValid || selection.isCollapsed) {
      _selectionLookupPending = false;
      _closeOwnedDictionary();
      return;
    }
    if (cause == SelectionChangedCause.longPress ||
        cause == SelectionChangedCause.drag) {
      _selectionLookupPending = true;
    }
    if (cause == SelectionChangedCause.longPress &&
        !_longPressFeedbackCompleted) {
      _longPressFeedbackCompleted = true;
      PlatformSelectionFeedback.completeEditableTextLongPress(
        context,
        hadFocusOnPointerDown: _hadFocusOnPointerDown,
      );
    }
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is PointerCancelEvent) {
      _selectionLookupPending = false;
      _longPressFeedbackCompleted = false;
      return;
    }
    if (event is! PointerUpEvent ||
        !_selectionLookupPending ||
        _selectionCommitScheduled) {
      return;
    }
    _selectionCommitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionCommitScheduled = false;
      if (mounted) _commitSelectionLookup();
    });
    _longPressFeedbackCompleted = false;
  }

  /// 手指松开后，以系统最终选区查询；保留字符级边界，只裁掉首尾空白。
  void _commitSelectionLookup() {
    if (!_selectionLookupPending) return;
    _selectionLookupPending = false;
    final selection = _currentSelection;
    if (selection == null || !selection.isValid || selection.isCollapsed) {
      return;
    }
    final start = selection.start.clamp(0, _fullText.length);
    final end = selection.end.clamp(0, _fullText.length);
    final selectedText = _fullText.substring(start, end).trim();
    if (selectedText.isNotEmpty) _lookup(selectedText);
  }

  // -- 选区操作条 --

  /// 句子正文只保留复制、收藏与问 AI，不暴露系统分享、全选等额外动作。
  Widget _buildSelectionToolbar(BuildContext context, EditableTextState state) {
    final l10n = AppLocalizations.of(context)!;
    final selectedWord = normalizeWord(_selectedTextOf(state));
    final isSaved =
        _pendingSavedWordStates[selectedWord] ??
        _savedWordTexts.contains(selectedWord);
    final aiEnabled = shouldShowAiChatAssistantEntry(
      chatbotEnabled: kChatbotEnabled,
      remoteEnabled: ref.read(
        remoteFeatureEnabledProvider(RemoteFeature.aiChatAssistant),
      ),
    );
    return SelectionToolbar(
      anchors: SelectionToolbar.anchorsForEditableText(state),
      actions: [
        SelectionToolbarAction(
          label: l10n.chatCopy,
          onPressed: () => _handleCopy(state),
        ),
        if (selectedWord.isNotEmpty)
          SelectionToolbarAction(
            label: isSaved
                ? l10n.favoritesUnsaveVocabulary
                : l10n.favoritesSaveVocabulary,
            onPressed: () => unawaited(
              _handleToggleSave(state, selectedWord, currentlySaved: isSaved),
            ),
          ),
        if (aiEnabled)
          SelectionToolbarAction(
            label: l10n.chatFollowUp,
            onPressed: () => _handleAskAi(state),
          ),
      ],
    );
  }

  String _selectedTextOf(EditableTextState state) {
    final value = state.textEditingValue;
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    return selection.textInside(value.text);
  }

  void _handleCopy(EditableTextState state) {
    final text = _selectedTextOf(state);
    if (text.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
    _clearEditableSelection(state);
  }

  /// 把选区按现有词汇规则收藏或取消收藏，并保留选区与查词面板。
  ///
  /// 收藏状态由 `saved_words` 的流式 Provider 同步到词典面板、正文收藏标记
  /// 和收藏页；来源信息与词典面板收藏入口保持完全一致。
  Future<void> _handleToggleSave(
    EditableTextState state,
    String word, {
    required bool currentlySaved,
  }) async {
    final selection = state.textEditingValue.selection;
    final notifier = ref.read(savedWordListProvider.notifier);
    try {
      if (currentlySaved) {
        await notifier.removeWord(word);
      } else {
        await notifier.saveWord(
          word: word,
          audioItemId: widget.origin.audioItemId,
          sentenceIndex: widget.origin.sentenceIndex,
          sentenceText: widget.origin.sentenceText,
          sentenceStartMs: widget.origin.sentenceStartMs,
          sentenceEndMs: widget.origin.sentenceEndMs,
        );
      }
      if (!mounted) return;
      final desiredSaved = !currentlySaved;
      final streamedWords =
          ref.read(savedWordTextsProvider).valueOrNull ?? const <String>{};
      setState(() {
        if (streamedWords.contains(word) == desiredSaved) {
          _pendingSavedWordStates.remove(word);
        } else {
          _pendingSavedWordStates[word] = desiredSaved;
        }
      });
      // 收藏流会重建正文 TextSpan；在该帧结束后恢复同一字符选区，并重建
      // Overlay 操作条，使“收藏 / 取消收藏”文案原地切换而不离开查词现场。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !selection.isValid || selection.isCollapsed) return;
        final value = state.textEditingValue;
        state.userUpdateTextEditingValue(
          value.copyWith(selection: selection),
          SelectionChangedCause.toolbar,
        );
        state.hideToolbar();
        state.showToolbar();
      });
    } catch (error, stackTrace) {
      debugPrint('[SelectableSentenceText] 收藏选区失败: $error\n$stackTrace');
    }
  }

  /// 清除系统选区会触发 [_handleSelectionChanged]，从而同步关闭当前查词面板。
  void _clearEditableSelection(EditableTextState state) {
    final value = state.textEditingValue;
    state.hideToolbar();
    state.userUpdateTextEditingValue(
      value.copyWith(
        selection: TextSelection.collapsed(
          offset: value.selection.extentOffset,
        ),
      ),
      SelectionChangedCause.toolbar,
    );
  }

  /// 关闭选区与词典后打开同一句子的聊天会话，并把选中文字放入引用待发送区。
  void _handleAskAi(EditableTextState state) {
    final selectedText = _selectedTextOf(state).trim();
    if (selectedText.isEmpty) return;
    final sourceSentence = widget.origin.sentenceText;
    final sentenceText = sourceSentence == null || sourceSentence.trim().isEmpty
        ? _fullText
        : sourceSentence;
    _clearEditableSelection(state);
    _closeOwnedDictionary();
    unawaited(
      showSentenceChatbotSheet(
        context: context,
        sentenceText: sentenceText,
        initialQuote: selectedText,
      ),
    );
  }

  // -- 构建 --

  /// 收藏标记掩码：(文本, 索引) 不变时复用缓存，变化时重算命中区间
  List<bool> _ensureSavedMask(SavedTextIndex index) {
    final text = _fullText;
    if (_savedMaskText == text && identical(_savedMaskIndex, index)) {
      return _savedMask;
    }
    final ranges = savedCharRanges(text, _tokens, index);
    final mask = ranges.isEmpty
        ? const <bool>[]
        : charMaskFromRanges(text.length, ranges);
    _savedMask = mask;
    _savedMaskText = text;
    _savedMaskIndex = index;
    return mask;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        widget.style ??
        theme.textTheme.titleMedium?.copyWith(
          height: 1.6,
          color: theme.colorScheme.onSurface,
        );
    ref.listen(savedWordTextsProvider, (previous, next) {
      final streamedWords = next.valueOrNull ?? const <String>{};
      final acknowledgedWords = [
        for (final entry in _pendingSavedWordStates.entries)
          if (streamedWords.contains(entry.key) == entry.value) entry.key,
      ];
      if (!mounted || acknowledgedWords.isEmpty) return;
      setState(() {
        for (final word in acknowledgedWords) {
          _pendingSavedWordStates.remove(word);
        }
      });
    });
    // 单词收藏集合同时供选区操作条判断“收藏 / 取消收藏”。
    _savedWordTexts =
        ref.watch(savedWordTextsProvider).valueOrNull ?? const <String>{};
    // 收藏索引流式监听：加载中/降级（测试环境无 DB）时为空索引 = 无标记
    final savedMask = _ensureSavedMask(ref.watch(savedTextIndexProvider));
    final rich = SelectableText.rich(
      key: _textKey,
      TextSpan(style: style, children: _buildSpans(theme, savedMask)),
      focusNode: _focusNode,
      // 默认 includeLineSpacingMiddle 会把 1.6 行高的额外 leading 算进高亮，
      // 造成截图中的文字/选区中线错位；tight 只贴合实际字形。
      selectionHeightStyle: ui.BoxHeightStyle.tight,
      onTap: _handleTap,
      onSelectionChanged: _handleSelectionChanged,
      contextMenuBuilder: _buildSelectionToolbar,
    );
    return PlatformTextSelectionStyle(
      child: Listener(
        onPointerDown: (event) {
          _lastPointerDownPosition = event.position;
          _hadFocusOnPointerDown = _focusNode.hasFocus;
          _longPressFeedbackCompleted = false;
        },
        child: rich,
      ),
    );
  }

  /// 逐 token 构建 span：评分片段染文字色，收藏命中加点状下划线。
  ///
  /// 收藏标记按 [savedMask] 的逐字符边界切分 token（如 "dog." 只给 "dog"
  /// 加下划线、句号不加），下划线颜色沿用「橙色 = 收藏」视觉语言（与意群
  /// 收藏色系一致），必须显式设 decorationColor（默认会跟随文字色）。
  List<InlineSpan> _buildSpans(ThemeData theme, List<bool> savedMask) {
    final savedColor = AppTheme.savedTextMarkColor(theme.brightness);
    final colorAt = _segmentColorLookup();
    final text = _fullText;
    final spans = <InlineSpan>[];
    for (final t in _tokens) {
      // token 颜色按其起点判定（与旧版整 token 染色一致），
      // 收藏掩码只切分下划线子段，不改变染色粒度
      final color = colorAt(t.start);
      for (final (subStart, subEnd, saved) in splitByMask(
        t.start,
        t.end,
        savedMask,
      )) {
        spans.add(
          TextSpan(
            text: text.substring(subStart, subEnd),
            style: TextStyle(
              color: color,
              decoration: saved ? TextDecoration.underline : null,
              decorationStyle: saved ? TextDecorationStyle.dotted : null,
              decorationColor: saved ? savedColor : null,
              decorationThickness: saved ? 2 : null,
            ),
          ),
        );
      }
    }
    return spans;
  }

  /// 评分片段颜色查询：字符偏移 → 文字色（无片段时恒 null）
  Color? Function(int) _segmentColorLookup() {
    final segs = widget.highlightedSegments;
    if (segs == null || segs.isEmpty) return (_) => null;
    // 预计算各片段的字符区间（拼接顺序即偏移顺序）
    final ranges = <(int, int, bool)>[];
    var offset = 0;
    for (final s in segs) {
      ranges.add((offset, offset + s.text.length, s.isMatched));
      offset += s.text.length;
    }
    return (charOffset) {
      for (final (start, end, matched) in ranges) {
        if (charOffset >= start && charOffset < end) {
          // 命中片段沿用既有跟读评分绿色
          return matched ? const Color(0xFF2E9B51) : null;
        }
      }
      return null;
    };
  }
}
