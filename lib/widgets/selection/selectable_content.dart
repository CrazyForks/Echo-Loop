/// 自有选区的交互内核（L1 会话 + L2 呈现的组装件）
///
/// 为什么不用 `SelectableText` / `SelectionArea`：两者都在**前台失焦时清空选区**
/// （`material/selectable_text.dart` 与 `widgets/selectable_region.dart` 的
/// `_handleFocusChanged`），且 `SelectableText` 还会在 `textSpan` 变化时重建
/// controller 让选区归零。而本项目要求「选中一段文字 → 在页面内面板里查词/切源/
/// 收藏 → 选区必须还在」，与那份契约直接冲突（见 CLAUDE.md §7.28）。
///
/// 分层：L1 [TextSelectionSession]（选区唯一真相源，只存字符区间，不含焦点概念——
/// 本组件的 [FocusNode] 只是键盘事件路由，失焦不影响选区）；L2 本文件 +
/// [SelectionPresentation] + 平台手柄 / tight 高亮 / 操作条 / 放大镜；L3
/// [SelectionBackend]（命中、词边界、几何、取文本，单段与跨块的唯一差异点）。
///
/// 本组件不知道业务（查词 / AI 回答）的存在：选区确认后只回调
/// [SelectableContent.onSelectionCommitted]，操作条内容由 `actionsBuilder` 提供。
///
/// **坐标约定**：后端矩形以 `backend.contentBox` 为参照系，而高亮画在 [child]
/// 那一层，因此组装件必须让两者原点一致（单段 = `RichText` 自身，跨块 = 容器自身）。
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/platform_selection_feedback.dart';
import 'platform_selection_handles.dart';
import 'selection_backend.dart';
import 'selection_extend.dart';
import 'selection_keyboard.dart';
import 'selection_highlight.dart';
import 'selection_magnifier.dart';
import 'selection_gesture_detector.dart';
import 'selection_presentation.dart';
import 'selection_toolbar.dart';
import 'selection_toolbar_layer.dart';
import 'text_selection_session.dart';
import 'unbounded_hit_stack.dart';

/// 自有选区的可选内容。
class SelectableContent extends StatefulWidget {
  const SelectableContent({
    super.key,
    required this.child,
    required this.backend,
    required this.contentIdentity,
    required this.actionsBuilder,
    this.toolbarOwner,
    this.tapSelectsWord = true,
    this.onSelectionCommitted,
    this.onBeforeSelectionCommitted,
    this.onSessionEnded,
    this.onShowToolbar,
    this.onHideToolbar,
  });

  /// 内容本体（`RichText` 或 markdown 子树）。
  final Widget child;

  /// 选区后端（由调用方创建并持有，实例需在组件生命周期内保持稳定）。
  final SelectionBackend backend;

  /// 内容身份：变化即结束会话，不按旧字符偏移盲目恢复。
  final String contentIdentity;

  /// 操作条动作；入参为当前选中文本。返回空列表则不显示操作条。
  final List<SelectionToolbarAction> Function(String selectedText)
  actionsBuilder;

  /// 操作条挂载请求的 owner 身份；默认用本内核的 state。
  ///
  /// 外层组装件（如 [AppSelectableText]）传自己的 state，好让业务层用同一个对象
  /// 调宿主的「收起我的操作条」——宿主按 owner 身份判定，不能张冠李戴。
  final Object? toolbarOwner;

  /// 单击是否选中该处的词。
  ///
  /// 查词正文为 true（点词即查）；AI 回答为 false（对齐平台文本：单击取消选区、
  /// 双击选词）。双击选词两者都有。
  final bool tapSelectsWord;

  /// 选区确认（点词或松手）时回调选中文本。
  final ValueChanged<String>? onSelectionCommitted;

  /// 选区确认**之前**的副作用钩子（如暂停自动推进）。
  final VoidCallback? onBeforeSelectionCommitted;

  /// 会话结束（点空白、内容变化、外部显式结束）时回调。
  final VoidCallback? onSessionEnded;

  /// 挂载/更新选区操作条。
  ///
  /// 操作条**必须由页面级宿主渲染**（见 `selection_toolbar_layer.dart`）：它会
  /// 溢出内容的 render box，而祖先按各自 box 剪裁命中测试，挂在内容自己的
  /// Stack 里溢出部分点不动。
  final ValueChanged<SelectionToolbarRequest>? onShowToolbar;

  /// 收起选区操作条；入参是本内容对应的 owner 身份（宿主据此只收自己那个）。
  ///
  /// 传 owner 而不是让业务层自己去查 state：**组件卸载后**也要能收操作条
  /// （聊天清空会话会直接把 AI 回答从树上摘掉，`currentState` / `context` 此时
  /// 都已失效），回调必须不依赖任何仍挂在树上的东西。
  final ValueChanged<Object>? onHideToolbar;

  @override
  State<SelectableContent> createState() => SelectableContentState();
}

/// [SelectableContent] 的 state。
///
/// 公开是为了让宿主能显式结束会话（[endSession]）并把命中区域注册给「点外关闭」
/// 屏障（[hitTest]）。
class SelectableContentState extends State<SelectableContent> {
  /// L1：选区唯一真相源。
  final TextSelectionSession _session = TextSelectionSession();

  /// L2：派生几何缓存。
  late final SelectionPresentation _presentation = SelectionPresentation(
    _backend,
  );

  SelectionBackend get _backend => widget.backend;

  /// 操作条挂载请求的 owner 身份（默认用本 state）。
  Object get _toolbarOwner => widget.toolbarOwner ?? this;

  bool _geometryUpdateScheduled = false;

  /// 选区的固定端（base）：扩选只移动另一端，保留字符级自由边界。
  /// 长按拖选、手柄拖拽、鼠标拖选、Shift+点击与 Shift+方向键共用。
  int? _selectionBase;

  /// 鼠标按下位置：拖动没形成选区时按「点击」兜底（见 [_handleMouseDragEnd]）。
  Offset? _mouseDownPosition;

  /// 点击节奏（自行判定双击，不用 DoubleTapGestureRecognizer）。
  final TapCadence _tapCadence = TapCadence();

  /// 键盘事件焦点（桌面 Shift+方向键扩选、Cmd/Ctrl+C 复制）。失焦不影响选区。
  final FocusNode _focusNode = FocusNode(debugLabel: 'SelectableContent');

  /// 拖选放大镜（移动端按平台渲染，桌面端自动不显示）。
  final SelectionMagnifier _magnifier = SelectionMagnifier();

  @override
  void didUpdateWidget(SelectableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 内容变了就结束会话，不按旧字符偏移盲目恢复（流式 AI 回答每帧都会走到）。
    if (oldWidget.contentIdentity != widget.contentIdentity &&
        _session.endIfContentChanged(widget.contentIdentity)) {
      _presentation.reset();
      _selectionBase = null;
      _hideMagnifier();
      // 收操作条与结束通知都会 setState 到**祖先**（宿主页面），当前正处在重建
      // 流程中，必须推迟一帧，否则触发「markNeedsBuild called during build」。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onHideToolbar?.call(_toolbarOwner);
        widget.onSessionEnded?.call();
      });
    }
  }

  @override
  void dispose() {
    _magnifier.dispose();
    _focusNode.dispose();
    // 卸载时收掉自己挂在宿主上的操作条：内容被整块摘掉（如聊天「新会话」清空
    // 消息）时不会走 didUpdateWidget，没人替我们收，操作条会孤零零留在页面上。
    // 卸载发生在宿主重建过程中，直接 setState 到宿主会「markNeedsBuild during
    // build」，所以推迟一帧；owner 与回调都先取好，dispose 之后不能再读 widget。
    final hide = widget.onHideToolbar;
    final owner = _toolbarOwner;
    if (hide != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => hide(owner));
    }
    super.dispose();
  }

  // -- 对外能力 --

  /// 是否有已确认的选区。
  bool get hasActiveSelection => _session.isActive;

  /// 当前选区字符区间（无选区为 null）。
  TextRange? get selectionRange => _session.range;

  /// 当前会话阶段。
  TextSelectionPhase get selectionPhase => _session.phase;

  /// 内容渲染盒（几何参照系）。公开给宿主与测试做几何断言。
  RenderBox? get contentBox => _backend.contentBox;

  /// 当前选中文本（无选区时为空串）。
  String get selectedText {
    final range = _session.range;
    return range == null ? '' : _backend.textIn(range);
  }

  /// 显式结束会话（面板关闭、别处发起查词、复制/问 AI 之后）。
  void endSession({bool notify = true}) {
    if (_session.phase == TextSelectionPhase.idle) return;
    setState(() {
      _session.end();
      _presentation.reset();
    });
    _selectionBase = null;
    _hideMagnifier();
    widget.onHideToolbar?.call(_toolbarOwner);
    if (notify) widget.onSessionEnded?.call();
  }

  /// 全局坐标是否命中本组件的交互区域（内容 bounds ∪ 手柄命中区）。
  ///
  /// 供「点面板外关闭」屏障做豁免判定，必须精确。
  bool hitTest(Offset globalPosition) {
    final box = contentBox;
    if (box == null) return false;
    final local = box.globalToLocal(globalPosition);
    if ((Offset.zero & box.size).contains(local)) return true;
    if (!_session.hasSelection) return false;
    return _presentation.hitsHandle(platformHandleControls(context), local);
  }

  // -- 手势：点击 --

  /// 单击：按 [SelectableContent.tapSelectsWord] 选词或取消选区；Shift+点击扩选；
  /// 双击一律选词（双击判定见 [TapCadence]）。
  void _handleTapUp(TapUpDetails details) {
    if (details.kind == PointerDeviceKind.mouse) _focusNode.requestFocus();
    final isDoubleTap = _tapCadence.isDoubleTap(details.globalPosition);
    _tapCadence.record(details.globalPosition);
    if (!isDoubleTap && HardwareKeyboard.instance.isShiftPressed) {
      final offset = _backend.offsetAt(details.globalPosition);
      if (offset != null && _extendSelectionToOffset(offset)) return;
    }
    if (isDoubleTap || widget.tapSelectsWord) {
      _selectWordAt(details.globalPosition);
      return;
    }
    endSession();
  }

  /// 点词：选中该词并提交；点在空白/标点上则取消选择。
  void _selectWordAt(Offset globalPosition) {
    final range = _backend.wordAt(globalPosition);
    if (range == null) {
      endSession();
      return;
    }
    _selectionBase = range.start;
    setState(() => _session.activate(range, widget.contentIdentity));
    _scheduleGeometryUpdate();
    _commit(range);
  }

  // -- 手势：拖选（长按 / 手柄 / 鼠标三条路径同构）--

  /// 本次拖选是否按词粒度扩选、是否显示放大镜（由发起方按平台约定决定）。
  bool _dragUsesWords = false;
  bool _dragShowsMagnifier = false;

  /// 开始拖选：固定 [base] 端，之后只移动另一端。
  ///
  /// [initialRange] 为空表示「起手还没有选区」（长按落在词间空白、鼠标刚按下），
  /// 拖出第一个字符时才真正建立会话。
  void _beginDrag({
    required int base,
    required TextRange? initialRange,
    required bool usesWords,
    required bool showsMagnifier,
    required Offset globalPosition,
    bool magnifierAtStart = false,
  }) {
    _selectionBase = base;
    _dragUsesWords = usesWords;
    _dragShowsMagnifier = showsMagnifier;
    if (initialRange == null) return;
    setState(
      () => _session.beginSelecting(initialRange, widget.contentIdentity),
    );
    _scheduleGeometryUpdate();
    if (showsMagnifier) {
      _showOrUpdateMagnifier(globalPosition, isStart: magnifierAtStart);
    }
  }

  void _updateDrag(Offset globalPosition) {
    final base = _selectionBase;
    final offset = _backend.offsetAt(globalPosition);
    if (base == null || offset == null) return;
    final range = rangeBetween(
      _backend,
      base,
      offset,
      wordGranularity: _dragUsesWords,
    );
    if (!range.isValid || range.isCollapsed) return;
    setState(() {
      if (_session.isSelecting) {
        _session.updateSelecting(range);
      } else {
        _session.beginSelecting(range, widget.contentIdentity);
      }
    });
    _scheduleGeometryUpdate();
    if (_dragShowsMagnifier) {
      _showOrUpdateMagnifier(globalPosition, isStart: offset < base);
    }
  }

  /// 松手：提交选区（未处于拖动阶段则什么都不做）。
  void _finishDrag() {
    _hideMagnifier();
    final range = _session.commitSelecting();
    setState(() {});
    if (range != null) _commit(range);
  }

  /// 拖动被取消：回到上一个确认态（选区保留）或结束会话。
  void _cancelDrag() {
    _hideMagnifier();
    setState(_session.cancelSelecting);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    final word = _backend.wordAt(details.globalPosition);
    // 长按落在词之间的空白/标点上：不立刻形成选区，但把锚点定在该字符，拖动起来
    // 就能选（平台长按任意位置都能起选区，直接 return 会变成死手势）。
    final base = word?.start ?? _backend.offsetAt(details.globalPosition);
    if (base == null) return;
    PlatformSelectionFeedback.forOwnedLongPressSelection(context);
    _beginDrag(
      base: base,
      initialRange: word,
      usesWords: longPressSelectsWords(Theme.of(context).platform),
      showsMagnifier: true,
      globalPosition: details.globalPosition,
    );
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) =>
      _updateDrag(details.globalPosition);

  /// 抓住一端后，另一端成为固定端；手柄拖拽在所有平台都是**字符级自由边界**。
  void _handleHandleDragStart(Offset globalPosition, {required bool isStart}) {
    final range = _session.range;
    if (range == null) return;
    _beginDrag(
      base: isStart ? range.end : range.start,
      initialRange: range,
      usesWords: false,
      showsMagnifier: true,
      globalPosition: globalPosition,
      magnifierAtStart: isStart,
    );
  }

  /// 鼠标按住拖动选择（桌面标准交互，一律字符级、无放大镜）。
  ///
  /// 触屏没有这条路径（recognizer 限定 [PointerDeviceKind.mouse]），所以不会与
  /// 长按拖选/滚动竞争；鼠标拖动一超过 slop 就赢下竞技场，长按要等 500ms 才接受。
  void _handleMouseDragStart(DragStartDetails details) {
    _focusNode.requestFocus();
    final base = _backend.offsetAt(details.globalPosition);
    _mouseDownPosition = details.globalPosition;
    if (base == null) return;
    _beginDrag(
      base: base,
      initialRange: null,
      usesWords: false,
      showsMagnifier: false,
      globalPosition: details.globalPosition,
    );
  }

  void _handleMouseDragEnd() {
    final downPosition = _mouseDownPosition;
    _mouseDownPosition = null;
    if (_session.isSelecting) {
      _finishDrag();
      return;
    }
    // 没拖出任何选区 = 用户其实是在点击。鼠标是精确指针，Flutter 的 slop 只有
    // 1 逻辑像素（kPrecisePointerHitSlop），手抖 2px 就会让 pan 赢下竞技场、tap
    // 落败；若不在这里兜底，桌面点词查词会偶发失灵。
    if (downPosition != null) {
      _handleTapUp(
        TapUpDetails(
          kind: PointerDeviceKind.mouse,
          globalPosition: downPosition,
        ),
      );
    }
  }

  void _handleMouseDragCancel() {
    _mouseDownPosition = null;
    _cancelDrag();
  }

  // -- 键盘（桌面）--

  /// 没有选区时不处理任何按键：本组件没有光标概念（选区是唯一状态），凭空按
  /// Shift+方向键无处可起。复制**保留选区**（平台标准），与操作条里业务定义的
  /// 「复制并结束会话」是两个动作。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final intent = selectionKeyIntentFor(event);
    if (intent == null) return KeyEventResult.ignored;
    final extent = _selectionExtent;
    final handled = switch (intent) {
      SelectionKeyIntent.copy => _copySelection(),
      SelectionKeyIntent.extendCharacterLeft => _extendTo(
        extent == null ? null : extent - 1,
      ),
      SelectionKeyIntent.extendCharacterRight => _extendTo(
        extent == null ? null : extent + 1,
      ),
      SelectionKeyIntent.extendLineUp => _extendTo(
        extent == null ? null : offsetInAdjacentLine(_backend, extent, -1),
      ),
      SelectionKeyIntent.extendLineDown => _extendTo(
        extent == null ? null : offsetInAdjacentLine(_backend, extent, 1),
      ),
    };
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// 复制当前选区到剪贴板；无选区返回 false（不消费按键）。
  bool _copySelection() {
    final text = selectedText;
    if (text.isEmpty) return false;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    return true;
  }

  /// 浮动端（非固定端）当前偏移；无选区返回 null。
  int? get _selectionExtent {
    final range = _session.range;
    final base = _selectionBase;
    if (range == null || base == null || !_session.hasSelection) return null;
    return extentOf(range, base);
  }

  bool _extendTo(int? offset) =>
      offset != null && _extendSelectionToOffset(offset);

  /// 保留固定端，把浮动端移到 [offset] 并确认（Shift+点击 / Shift+方向键共用）。
  bool _extendSelectionToOffset(int offset) {
    final base = _selectionBase;
    if (base == null || !_session.hasSelection) return false;
    final clamped = offset.clamp(0, _backend.contentLength);
    if (clamped == base) {
      // 缩回到固定端 = 选区归零：结束会话（本实现没有光标态）。
      endSession();
      return true;
    }
    final range = rangeBetween(_backend, base, clamped, wordGranularity: false);
    if (!range.isValid || range.isCollapsed || range == _session.range) {
      return false;
    }
    setState(() => _session.activate(range, widget.contentIdentity));
    _scheduleGeometryUpdate();
    _commit(range);
    return true;
  }

  /// 提交选区：先跑副作用钩子，再回调选中文本。
  void _commit(TextRange range) {
    final text = _backend.textIn(range);
    if (text.trim().isEmpty) {
      endSession();
      return;
    }
    widget.onBeforeSelectionCommitted?.call();
    widget.onSelectionCommitted?.call(text);
  }

  // -- 几何 --

  /// post-frame 重算几何：选区变化、旋屏、字号、行高重排后渲染节点才有最新的
  /// box。只在结果变化时 setState，因此可以在 build 里无条件安排。
  void _scheduleGeometryUpdate() {
    if (_geometryUpdateScheduled) return;
    _geometryUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryUpdateScheduled = false;
      if (!mounted) return;
      if (_presentation.refresh(_session.range)) setState(() {});
      // 几何没变但会话阶段可能变了（拖动结束 → 已确认才显示操作条），所以无条件
      // 同步；宿主按请求相等性去重，不会引起重建循环。
      _syncToolbar();
    });
  }

  /// 把操作条请求同步给宿主。
  ///
  /// 只在选区**已确认**时显示：拖动期间藏起来（业界标准，且此时放大镜在显示）。
  /// 锚点用全局坐标，由宿主换算到自己的坐标系。
  void _syncToolbar() {
    final show = widget.onShowToolbar;
    final hide = widget.onHideToolbar;
    if (show == null || hide == null) return;
    if (!_session.isActive) {
      hide(_toolbarOwner);
      return;
    }
    final request = _presentation.toolbarRequest(
      owner: _toolbarOwner,
      actions: widget.actionsBuilder(selectedText),
    );
    if (request == null) {
      hide(_toolbarOwner);
      return;
    }
    show(request);
  }

  // -- 放大镜 --

  void _showOrUpdateMagnifier(Offset globalPosition, {required bool isStart}) {
    final range = _session.range;
    if (range == null) return;
    _magnifier.showForSelection(
      context: context,
      debugRequiredFor: widget,
      backend: _backend,
      range: range,
      globalGesturePosition: globalPosition,
      isStart: isStart,
    );
  }

  void _hideMagnifier() => _magnifier.hide();

  // -- 构建 --

  @override
  Widget build(BuildContext context) {
    // 有选区时每帧校正几何（只在结果变化时 setState）。
    if (_session.hasSelection) _scheduleGeometryUpdate();
    return SelectionGestureDetector(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      onTapUp: _handleTapUp,
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: (_) => _finishDrag(),
      onMouseDragStart: _handleMouseDragStart,
      onMouseDragUpdate: (details) => _updateDrag(details.globalPosition),
      onMouseDragEnd: _handleMouseDragEnd,
      onMouseDragCancel: _handleMouseDragCancel,
      child: UnboundedHitStack(
        children: [
          CustomPaint(
            // painter 在 child 之前绘制 → 高亮在文字下面。
            painter: SelectionHighlightPainter(
              rects: _presentation.highlightRects,
              color: resolveSelectionColor(context),
            ),
            child: widget.child,
          ),
          ..._buildHandles(),
        ],
      ),
    );
  }

  /// 选区手柄（平台画笔；桌面平台的画笔尺寸为空，自动不显示）。
  List<Widget> _buildHandles() {
    final startAnchor = _presentation.startAnchor;
    final endAnchor = _presentation.endAnchor;
    if (!_session.hasSelection || startAnchor == null || endAnchor == null) {
      return const [];
    }
    final controls = platformHandleControls(context);
    return [
      SelectionHandle(
        key: const Key('selection_handle_start'),
        controls: controls,
        anchor: startAnchor,
        isStart: true,
        onDragStart: (offset) => _handleHandleDragStart(offset, isStart: true),
        onDragUpdate: _updateDrag,
        onDragEnd: _finishDrag,
        onDragCancel: _cancelDrag,
      ),
      SelectionHandle(
        key: const Key('selection_handle_end'),
        controls: controls,
        anchor: endAnchor,
        isStart: false,
        onDragStart: (offset) => _handleHandleDragStart(offset, isStart: false),
        onDragUpdate: _updateDrag,
        onDragEnd: _finishDrag,
        onDragCancel: _cancelDrag,
      ),
    ];
  }
}
