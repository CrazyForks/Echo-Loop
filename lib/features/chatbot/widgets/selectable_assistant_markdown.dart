/// 可选中的 AI 回答 markdown：官方 SelectionArea + 自定义选区操作条（复制 / 问 AI）。
///
/// 采用 Flutter 标准文本选择方案（[SelectionArea] + `contextMenuBuilder`），三端一致、
/// 贴官方惯用法，不接管手柄或桌面分支；仅补齐移动端初始长按放大镜：
/// - 长按/拖拽手柄自由选中任意连续文本（跨 markdown 块、含行内代码 `` `code` ``）；
/// - 选区完成后在选区上方中间弹出操作条（复制 / 问 AI）；
/// - 「点已选中文本切换操作条显隐、点选区外清除选区」均由框架原生处理，本组件不干预。
///
/// 内部复用 [MarkdownMessage]（`selectable: false`，选区统一由本组件的 [SelectionArea]
/// 接管），保持 markdown 渲染逻辑单一来源。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/platform_selection_feedback.dart';
import '../../../widgets/common/platform_text_selection_style.dart';
import 'markdown_message.dart';
import 'selection_toolbar.dart';

/// AI 回答 markdown（可选中）。
///
/// - [data]：markdown 源文本；
/// - [style]：文字样式（随气泡主题传入）；
/// - [onFollowUp]：点「问 AI」时回调，携带当前选区纯文本；为空则不显示该按钮。
class SelectableAssistantMarkdown extends StatefulWidget {
  const SelectableAssistantMarkdown({
    super.key,
    required this.data,
    this.style,
    this.onFollowUp,
  });

  final String data;
  final TextStyle? style;
  final void Function(String selectedText)? onFollowUp;

  @override
  State<SelectableAssistantMarkdown> createState() =>
      _SelectableAssistantMarkdownState();
}

class _SelectableAssistantMarkdownState
    extends State<SelectableAssistantMarkdown> {
  /// 选区宿主几何，用于把初始长按放大镜限制在当前 AI 回答内。
  final GlobalKey _selectionAreaKey = GlobalKey();

  /// 当前选区纯文本（由 `onSelectionChanged` 跟踪，供复制/问 AI 读取）。
  String _selectedText = '';

  /// 初始长按放大镜；已有选区的手柄拖动仍由 Flutter 官方 overlay 负责。
  final MagnifierController _magnifierController = MagnifierController();
  final ValueNotifier<MagnifierInfo> _magnifierInfo =
      ValueNotifier<MagnifierInfo>(MagnifierInfo.empty);
  Timer? _longPressTimer;
  bool _pointerDown = false;
  bool _armedForInitialSelection = false;
  bool _hadSelectionOnPointerDown = false;
  bool _selectionChangedSincePointerDown = false;
  bool _longPressThresholdReached = false;
  bool _initialInteractionStarted = false;
  bool _hasSelection = false;
  Offset _lastPointerGlobal = Offset.zero;
  Offset _pointerDownGlobal = Offset.zero;

  bool get _supportsMobileSelection =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _magnifierController.hide();
    _magnifierInfo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 与句子正文共用平台标准背景和手柄色，不继承 App 品牌主题。
    return PlatformTextSelectionStyle(
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: (_) => _finishPointerInteraction(),
        onPointerCancel: (_) => _finishPointerInteraction(),
        child: SelectionArea(
          key: _selectionAreaKey,
          contextMenuBuilder: _buildToolbar,
          magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
          onSelectionChanged: _handleSelectionChanged,
          child: MarkdownMessage(
            data: widget.data,
            selectable: false,
            style: widget.style,
          ),
        ),
      ),
    );
  }

  /// 武装移动端长按；已有选区时若先发生明显拖动，会判定为拖手柄并退出补充路径。
  void _handlePointerDown(PointerDownEvent event) {
    if (!_supportsMobileSelection ||
        (event.kind != PointerDeviceKind.touch &&
            event.kind != PointerDeviceKind.stylus &&
            event.kind != PointerDeviceKind.invertedStylus)) {
      return;
    }
    _pointerDown = true;
    _armedForInitialSelection = true;
    _hadSelectionOnPointerDown = _hasSelection;
    _selectionChangedSincePointerDown = false;
    _longPressThresholdReached = false;
    _initialInteractionStarted = false;
    _lastPointerGlobal = event.position;
    _pointerDownGlobal = event.position;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(kLongPressTimeout, () {
      _longPressThresholdReached = true;
      _maybeStartInitialSelectionInteraction();
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointerDown) return;
    _lastPointerGlobal = event.position;
    if (_hadSelectionOnPointerDown &&
        (event.position - _pointerDownGlobal).distance > kTouchSlop) {
      _armedForInitialSelection = false;
      _longPressTimer?.cancel();
      _hideInitialMagnifier();
      return;
    }
    if (_magnifierController.overlayEntry != null) {
      _showOrUpdateInitialMagnifier();
    }
  }

  void _handleSelectionChanged(SelectedContent? content) {
    final nextText = content?.plainText ?? '';
    if (_pointerDown && nextText != _selectedText) {
      _selectionChangedSincePointerDown = true;
    }
    _selectedText = nextText;
    _hasSelection = content != null;
    if (!_hasSelection) {
      _hideInitialMagnifier();
      return;
    }
    _maybeStartInitialSelectionInteraction();
  }

  /// 长按阈值与非空选区都成立后，只启动一次反馈和初始放大镜。
  void _maybeStartInitialSelectionInteraction() {
    if (!_pointerDown ||
        !_armedForInitialSelection ||
        !_selectionChangedSincePointerDown ||
        !_longPressThresholdReached ||
        !_hasSelection ||
        _initialInteractionStarted ||
        !mounted) {
      return;
    }
    _initialInteractionStarted = true;
    PlatformSelectionFeedback.completeSelectableRegionLongPress(context);
    _showOrUpdateInitialMagnifier();
  }

  void _finishPointerInteraction() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pointerDown = false;
    _armedForInitialSelection = false;
    _hadSelectionOnPointerDown = false;
    _selectionChangedSincePointerDown = false;
    _longPressThresholdReached = false;
    _initialInteractionStarted = false;
    _hideInitialMagnifier();
  }

  /// 使用 Flutter 自适应放大镜外观；只补官方 `SelectionArea` 缺失的初始长按阶段。
  void _showOrUpdateInitialMagnifier() {
    if (!mounted) return;
    final info = _buildMagnifierInfo();
    if (info == null) return;
    _magnifierInfo.value = info;
    if (_magnifierController.overlayEntry != null) return;
    final magnifier = TextMagnifier.adaptiveMagnifierConfiguration
        .magnifierBuilder(context, _magnifierController, _magnifierInfo);
    if (magnifier == null) return;
    _magnifierController.show(
      context: context,
      debugRequiredFor: widget,
      builder: (_) => KeyedSubtree(
        key: const ValueKey('assistant_initial_selection_magnifier'),
        child: magnifier,
      ),
    );
  }

  void _hideInitialMagnifier() {
    if (_magnifierController.overlayEntry == null) return;
    _magnifierController.hide();
  }

  /// 将手指和回答区域转换到 root overlay，生成自适应放大镜所需几何。
  MagnifierInfo? _buildMagnifierInfo() {
    final overlay = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    final region = _selectionAreaKey.currentContext?.findRenderObject();
    if (overlay is! RenderBox || region is! RenderBox) return null;

    final fieldTopLeft = overlay.globalToLocal(
      region.localToGlobal(Offset.zero),
    );
    final fieldBottomRight = overlay.globalToLocal(
      region.localToGlobal(region.size.bottomRight(Offset.zero)),
    );
    final fieldBounds = Rect.fromPoints(fieldTopLeft, fieldBottomRight);
    final gesture = overlay.globalToLocal(_lastPointerGlobal);
    final fontSize = widget.style?.fontSize ?? 16;
    final lineHeight = fontSize * (widget.style?.height ?? 1.35);
    final caretRect = Rect.fromLTWH(
      gesture.dx,
      gesture.dy - lineHeight / 2,
      0,
      lineHeight,
    );
    return MagnifierInfo(
      globalGesturePosition: gesture,
      caretRect: caretRect,
      fieldBounds: fieldBounds,
      currentLineBoundaries: Rect.fromLTRB(
        fieldBounds.left,
        caretRect.top,
        fieldBounds.right,
        caretRect.bottom,
      ),
    );
  }

  /// 选区操作条：选区完成后在选区上方中间自动弹出「复制 / 问 AI」（选择/改选过程中
  /// 由框架自动隐藏，settle 后才弹）。
  ///
  /// 气泡样式与按钮交互由可复用组件 [SelectionToolbar] 承载；本组件只提供锚点与动作。
  Widget _buildToolbar(BuildContext context, SelectableRegionState state) {
    final l10n = AppLocalizations.of(context)!;
    return SelectionToolbar(
      anchors: SelectionToolbar.anchorsForSelection(state),
      actions: [
        SelectionToolbarAction(
          label: l10n.chatCopy,
          onPressed: () => _handleCopy(state),
        ),
        if (widget.onFollowUp != null)
          SelectionToolbarAction(
            label: l10n.chatFollowUp,
            onPressed: () => _handleFollowUp(state),
          ),
      ],
    );
  }

  /// 复制：写入剪贴板，收起操作条并清空选区。
  void _handleCopy(SelectableRegionState state) {
    final text = _selectedText;
    if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
    state.hideToolbar();
    state.clearSelection();
  }

  /// 问 AI：先取选区文本再清空（[SelectableRegionState.clearSelection] 会同步触发
  /// `onSelectionChanged` 把 [_selectedText] 置空），收起操作条后回调。
  void _handleFollowUp(SelectableRegionState state) {
    final text = _selectedText;
    state.hideToolbar();
    state.clearSelection();
    if (text.trim().isNotEmpty) widget.onFollowUp?.call(text);
  }
}
