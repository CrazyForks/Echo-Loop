/// 可点词 + 系统标准选区的句子文本组件（统一标注卡与盲听偷看两套点词实现）
///
/// - 点单词：用系统选区选中该词并立即查询；
/// - 长按：由 Flutter 建立平台默认选区并显示系统手柄；
/// - 拖动手柄：保持系统标准字符级选区，松手后查询最终选中文本。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

/// 真机查词时序日志；仅 debug 构建输出，统一使用微秒时间戳便于跨组件对齐。
void _traceDictionarySelection(String message) {
  if (!kDebugMode) return;
  final timestamp = DateTime.now().toIso8601String();
  debugPrint('[DictionaryTrace][$timestamp][selection] $message');
}

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

class _SelectableSentenceTextState extends ConsumerState<SelectableSentenceText>
    with WidgetsBindingObserver {
  /// 系统可选文本的 key，用于保留点词时的精确命中判断。
  final GlobalKey _textKey = GlobalKey();

  /// 系统选区焦点；面板关闭或其它句子发起查词时用于清除旧选区。
  final FocusNode _focusNode = FocusNode();

  /// 分词结果（text/segments 变化时重建）
  late List<WordToken> _tokens = tokenizeSentence(_fullText);

  /// Flutter 当前选区；长按/拖动期间只记录，直到手指松开才触发查词。
  TextSelection? _currentSelection;

  /// 当前查词会话确认的字符选区。
  ///
  /// Flutter 可能因面板交互、系统前后台切换临时释放 EditableText selection；
  /// 该快照只在用户显式结束会话时清除，是选区持久性的单一来源。
  TextSelection? _sessionSelection;

  bool _selectionLookupPending = false;
  bool _selectionCommitScheduled = false;
  bool _selectionPresentationScheduled = false;
  bool _pendingRestoreSelection = false;
  bool _pendingRequestToolbar = false;
  bool _toolbarHiddenByPanel = false;

  /// 当前仍按下的指针；多指或系统手柄交互全部结束后才提交最终选区。
  final Set<int> _activePointers = {};

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
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_handleFocusChanged);
    // 系统选择手柄位于 Overlay，组件自身 Listener 收不到手柄松开事件，
    // 因此监听全局指针序列，在全部指针松开后提交 Flutter 产生的最终选区。
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
      _sessionSelection = null;
      _selectionLookupPending = false;
      _focusNode.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeOwnedDictionary();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 面板打开时，正文区域仍可继续单击或长按查词。
    final host = DictionaryPanelHost.maybeOf(context);
    if (!identical(host, _host)) {
      _host?.unregisterTapThroughHitTest(_hitsTapThrough);
      _host?.panelTopListenable.removeListener(_handlePanelTopChanged);
      _host = host;
      _host?.registerTapThroughHitTest(_hitsTapThrough);
      _host?.panelTopListenable.addListener(_handlePanelTopChanged);
    }
    // 面板关闭或其它组件发起查词时，清除当前系统选区。回调执行前再次
    // 核对所有权，避免同帧内 show 后的旧回调清掉刚恢复的选区与操作条。
    final owner = DictionaryPanelHost.activeOwnerOf(context);
    if (!identical(owner, this)) {
      _sessionSelection = null;
      _toolbarHiddenByPanel = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _focusNode.hasFocus &&
            !(_host?.isOwnedBy(this) ?? false)) {
          _focusNode.unfocus();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _host?.unregisterTapThroughHitTest(_hitsTapThrough);
    _host?.panelTopListenable.removeListener(_handlePanelTopChanged);
    _focusNode.removeListener(_handleFocusChanged);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _focusNode.dispose();
    super.dispose();
  }

  /// 系统切到后台会主动销毁 selection overlay；回到前台时只为仍存续的
  /// 当前查词会话恢复焦点和操作条，避免误激活已经关闭或切换 owner 的选区。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !(_host?.isOwnedBy(this) ?? false)) {
      return;
    }
    _scheduleSelectionPresentationSync(
      restoreSelection: true,
      requestToolbar: true,
    );
  }

  void _handlePanelTopChanged() {
    _scheduleSelectionPresentationSync();
  }

  /// 面板会话存续期间，焦点变化只属于展示层变化，不等价于取消选区。
  void _handleFocusChanged() {
    if (_focusNode.hasFocus || !(_host?.isOwnedBy(this) ?? false)) return;
    _scheduleSelectionPresentationSync(
      restoreSelection: true,
      requestToolbar: true,
    );
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
    _traceDictionarySelection(
      'lookup owner=${identityHashCode(this)} text="$text" '
      'selection=$_currentSelection active=$_activePointers',
    );
    final selection = _currentSelection;
    if (selection != null && selection.isValid && !selection.isCollapsed) {
      _sessionSelection = selection;
    }
    widget.onBeforeLookup?.call();
    DictionaryPanelHost.of(
      context,
    ).show(widget.origin.queryFor(text), owner: this);
    _scheduleSelectionPresentationSync(requestToolbar: true);
  }

  /// 把持久选区投影到 Flutter 的焦点、手柄与操作栏展示层。
  ///
  /// 面板遮住任一选区文本框时只隐藏操作栏；再次露出后自动恢复。所有异步
  /// 回调执行前都重新核对 owner，防止旧帧复活已经结束的查词会话。
  void _scheduleSelectionPresentationSync({
    bool restoreSelection = false,
    bool requestToolbar = false,
  }) {
    _pendingRestoreSelection |= restoreSelection;
    _pendingRequestToolbar |= requestToolbar;
    if (_selectionPresentationScheduled) return;
    _selectionPresentationScheduled = true;
    _traceDictionarySelection(
      'presentation.schedule owner=${identityHashCode(this)} '
      'restore=$restoreSelection toolbar=$requestToolbar',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionPresentationScheduled = false;
      final shouldRestoreSelection = _pendingRestoreSelection;
      final shouldRequestToolbar = _pendingRequestToolbar;
      _pendingRestoreSelection = false;
      _pendingRequestToolbar = false;
      if (!mounted || !(_host?.isOwnedBy(this) ?? false)) {
        _traceDictionarySelection(
          'presentation.skip owner=${identityHashCode(this)} mounted=$mounted '
          'owned=${_host?.isOwnedBy(this) ?? false}',
        );
        return;
      }
      final state = _editableState;
      final selection = _sessionSelection;
      if (state == null ||
          selection == null ||
          !selection.isValid ||
          selection.isCollapsed) {
        _traceDictionarySelection(
          'presentation.skip owner=${identityHashCode(this)} '
          'selection=$selection',
        );
        return;
      }
      final displayedSelection = state.textEditingValue.selection;
      if (shouldRestoreSelection || displayedSelection != selection) {
        _focusNode.requestFocus();
        final value = state.textEditingValue;
        state.userUpdateTextEditingValue(
          value.copyWith(selection: selection),
          SelectionChangedCause.toolbar,
        );
      }
      final panelTop = _host?.panelTopListenable.value;
      final obscured =
          panelTop != null &&
          _selectionCrossesPanelTop(state, selection, panelTop);
      final wasHiddenByPanel = _toolbarHiddenByPanel;
      if (obscured) {
        state.hideToolbar(false);
        _toolbarHiddenByPanel = true;
      } else {
        _toolbarHiddenByPanel = false;
        if (shouldRequestToolbar ||
            shouldRestoreSelection ||
            wasHiddenByPanel) {
          state.showToolbar();
        }
      }
      _traceDictionarySelection(
        'presentation.sync owner=${identityHashCode(this)} '
        'selection=$selection panelTop=$panelTop obscured=$obscured '
        'hiddenByPanel=$_toolbarHiddenByPanel',
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _selectionCrossesPanelTop(
    EditableTextState state,
    TextSelection selection,
    double panelTop,
  ) {
    final editable = state.renderEditable;
    final boxes = editable.getBoxesForSelection(selection);
    for (final box in boxes) {
      final bottom = editable.localToGlobal(Offset(0, box.bottom)).dy;
      if (bottom > panelTop) return true;
    }
    return false;
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
    final pendingBefore = _selectionLookupPending;
    _currentSelection = selection;
    if (!selection.isValid || selection.isCollapsed) {
      _selectionLookupPending = false;
      if (!(_host?.isOwnedBy(this) ?? false)) {
        _sessionSelection = null;
      }
      _traceDictionarySelection(
        'selection.changed owner=${identityHashCode(this)} cause=$cause '
        'selection=$selection active=$_activePointers '
        'pending=$pendingBefore->false',
      );
      return;
    }
    _sessionSelection = selection;
    if (cause == SelectionChangedCause.longPress ||
        cause == SelectionChangedCause.drag) {
      _selectionLookupPending = true;
    }
    _traceDictionarySelection(
      'selection.changed owner=${identityHashCode(this)} cause=$cause '
      'selection=$selection active=$_activePointers '
      'pending=$pendingBefore->$_selectionLookupPending',
    );
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
    if (event is PointerDownEvent) {
      _activePointers.add(event.pointer);
      _traceDictionarySelection(
        'pointer.down owner=${identityHashCode(this)} pointer=${event.pointer} '
        'position=${event.position} active=$_activePointers '
        'pending=$_selectionLookupPending',
      );
      return;
    }
    if (event is PointerCancelEvent) {
      _activePointers.remove(event.pointer);
      if (_activePointers.isEmpty) {
        _selectionLookupPending = false;
        _longPressFeedbackCompleted = false;
        if (!(_host?.isOwnedBy(this) ?? false)) {
          _sessionSelection = null;
        }
      }
      _traceDictionarySelection(
        'pointer.cancel owner=${identityHashCode(this)} '
        'pointer=${event.pointer} active=$_activePointers '
        'pending=$_selectionLookupPending',
      );
      return;
    }
    if (event is PointerUpEvent) {
      _activePointers.remove(event.pointer);
      _traceDictionarySelection(
        'pointer.up owner=${identityHashCode(this)} pointer=${event.pointer} '
        'active=$_activePointers pending=$_selectionLookupPending '
        'scheduled=$_selectionCommitScheduled',
      );
    }
    if (event is! PointerUpEvent ||
        _activePointers.isNotEmpty ||
        _selectionCommitScheduled) {
      return;
    }
    _selectionCommitScheduled = true;
    _traceDictionarySelection(
      'commit.schedule owner=${identityHashCode(this)} '
      'selection=$_currentSelection',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionCommitScheduled = false;
      _traceDictionarySelection(
        'commit.frame owner=${identityHashCode(this)} mounted=$mounted '
        'active=$_activePointers pending=$_selectionLookupPending '
        'selection=$_currentSelection',
      );
      if (mounted) _finalizeSelectionGesture();
    });
    // addPostFrameCallback 本身不会请求新帧；真机 PointerUp 后若界面静止，
    // 回调会一直等到其它动画偶然产帧，造成多词查询秒级延迟。
    WidgetsBinding.instance.ensureVisualUpdate();
    _longPressFeedbackCompleted = false;
  }

  /// 所有指针松开后再处理最终选区。
  ///
  /// PointerDown、长按等待和拖动期间绝不结束查词会话；普通点击的 selection
  /// 变化发生在全局 PointerUp 之后，因此统一延迟一帧读取最终状态。折叠选区
  /// 代表用户取消选择，非折叠选区则仅在长按/拖动产生待查询时提交查词。
  void _finalizeSelectionGesture() {
    final selection = _currentSelection;
    if (selection == null || !selection.isValid || selection.isCollapsed) {
      _selectionLookupPending = false;
      _sessionSelection = null;
      _toolbarHiddenByPanel = false;
      _closeOwnedDictionary();
      return;
    }
    if (_selectionLookupPending) _commitSelectionLookup();
  }

  /// 手指松开后，以系统最终选区查询；保留字符级边界，只裁掉首尾空白。
  void _commitSelectionLookup() {
    if (!_selectionLookupPending) {
      _traceDictionarySelection(
        'commit.skip owner=${identityHashCode(this)} reason=notPending',
      );
      return;
    }
    _selectionLookupPending = false;
    final selection = _currentSelection;
    if (selection == null || !selection.isValid || selection.isCollapsed) {
      _traceDictionarySelection(
        'commit.skip owner=${identityHashCode(this)} '
        'reason=invalidSelection selection=$selection',
      );
      return;
    }
    final start = selection.start.clamp(0, _fullText.length);
    final end = selection.end.clamp(0, _fullText.length);
    final selectedText = _fullText.substring(start, end).trim();
    _traceDictionarySelection(
      'commit.selection owner=${identityHashCode(this)} '
      'range=$start..$end text="$selectedText"',
    );
    if (!hasDictionaryLookupContent(selectedText)) {
      _sessionSelection = null;
      _toolbarHiddenByPanel = false;
      _closeOwnedDictionary();
      return;
    }
    _lookup(selectedText);
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
    _closeOwnedDictionary();
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
      if (selection.isValid && !selection.isCollapsed) {
        _sessionSelection = selection;
        _scheduleSelectionPresentationSync(
          restoreSelection: true,
          requestToolbar: true,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[SelectableSentenceText] 收藏选区失败: $error\n$stackTrace');
    }
  }

  /// 仅清除系统选区；是否结束查词会话由复制、问 AI 等显式动作决定。
  void _clearEditableSelection(EditableTextState state) {
    final value = state.textEditingValue;
    _sessionSelection = null;
    _toolbarHiddenByPanel = false;
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
      if (!mounted) return;
      if (acknowledgedWords.isNotEmpty) {
        setState(() {
          for (final word in acknowledgedWords) {
            _pendingSavedWordStates.remove(word);
          }
        });
      }
      // 面板标题栏也能收藏。其数据库流会重建正文收藏下划线，Flutter
      // 可能随之释放内部 selection；只要查词会话仍归本组件所有，就把同一
      // 字符选区重新投影回来，收藏操作不得改变面板、选区或操作栏状态。
      final selection = _sessionSelection;
      if ((_host?.isOwnedBy(this) ?? false) &&
          selection != null &&
          selection.isValid &&
          !selection.isCollapsed) {
        _scheduleSelectionPresentationSync(
          restoreSelection: true,
          requestToolbar: true,
        );
      }
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
