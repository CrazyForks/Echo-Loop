/// 可选中的 AI 回答 markdown：与句子正文同一套自有选区实现。
///
/// 2026-07-30 由官方 `SelectionArea` 迁到 [SelectableContent] + 跨块后端
/// [MultiParagraphSelectionBackend]（见 CLAUDE.md §7.28）。迁移动机：
/// - **体验统一**：句子正文与 AI 回答的长按拖选、手柄、放大镜、操作条、桌面
///   鼠标拖选 / 双击选词 / Shift+点击 / Shift+方向键 / Cmd+C 全部同一份实现，
///   不再有「两处文本行为不一样」；
/// - 顺带去掉了三件补丁：官方 `SelectionArea` 缺失的初始长按放大镜（原先用
///   Listener + 计时器自己补）、失焦即清选区、流式 markdown 与 selectable
///   注册表的重入（`ConcurrentModificationError`）。
///
/// 内部复用 [MarkdownMessage]（纯渲染，选区统一由本组件接管），保持 markdown
/// 渲染逻辑单一来源。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/platform_text_selection_style.dart';
import '../../../widgets/selection/multi_paragraph_selection_backend.dart';
import '../../../widgets/selection/selectable_content.dart';
import '../../../widgets/selection/selection_backend.dart';
import '../../../widgets/selection/selection_toolbar.dart';
import '../../../widgets/selection/selection_toolbar_host.dart';
import 'markdown_message.dart';

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
  /// markdown 子树根：跨块几何的参照系（高亮也画在这一层）。
  final GlobalKey _contentKey = GlobalKey();

  final GlobalKey<SelectableContentState> _selectionKey =
      GlobalKey<SelectableContentState>();

  /// L3：跨块后端。词边界不注入业务分词，用段落 ICU 边界（能正确切中日韩文本）。
  late final SelectionBackend _backend = MultiParagraphSelectionBackend(
    container: () {
      final object = _contentKey.currentContext?.findRenderObject();
      return object is RenderBox ? object : null;
    },
  );

  /// 页面级操作条挂载点（聊天载体的 [SelectionToolbarHost]）。
  ///
  /// 缓存成字段而不是每次查：本组件会被整块摘掉（聊天「新会话」清空消息），
  /// 卸载后还要用它收掉操作条，那时 `context` 已失效。
  SelectionToolbarMount? _mount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mount = SelectionToolbarScope.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    // 与句子正文共用平台标准背景和手柄色，不继承 App 品牌主题。
    return PlatformTextSelectionStyle(
      child: SelectableContent(
        key: _selectionKey,
        backend: _backend,
        contentIdentity: widget.data,
        // 对齐平台文本：单击取消选区、双击选词（句子正文才是「点词即查」）。
        tapSelectsWord: false,
        actionsBuilder: _buildActions,
        onShowToolbar: (request) => _mount?.showSelectionToolbar(request),
        onHideToolbar: (owner) => _mount?.hideSelectionToolbar(owner),
        child: KeyedSubtree(
          key: _contentKey,
          child: MarkdownMessage(data: widget.data, style: widget.style),
        ),
      ),
    );
  }

  /// 操作条动作：复制 / 问 AI。
  List<SelectionToolbarAction> _buildActions(String selectedText) {
    if (selectedText.trim().isEmpty) return const [];
    final l10n = AppLocalizations.of(context)!;
    return [
      SelectionToolbarAction(
        label: l10n.chatCopy,
        onPressed: () => _handleCopy(selectedText),
      ),
      if (widget.onFollowUp != null)
        SelectionToolbarAction(
          label: l10n.chatFollowUp,
          onPressed: () => _handleFollowUp(selectedText),
        ),
    ];
  }

  /// 复制：写入剪贴板并结束选区会话（显式动作，与 Cmd+C 保留选区不同）。
  void _handleCopy(String selectedText) {
    if (selectedText.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: selectedText)));
    }
    _selectionKey.currentState?.endSession();
  }

  /// 问 AI：先结束选区，再把选中文字交给载体放入引用待发送区。
  void _handleFollowUp(String selectedText) {
    final text = selectedText.trim();
    _selectionKey.currentState?.endSession();
    if (text.isNotEmpty) widget.onFollowUp?.call(text);
  }
}
