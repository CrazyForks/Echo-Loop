/// 选区操作条：三端一致的横向灰色圆角胶囊，浮在选区上方（空间不足翻到下方）。
///
/// 独立、可复用：不与「聊天/markdown」耦合。传入选区锚点
/// （[TextSelectionToolbarAnchors]，**全局坐标**）与若干动作项
/// （[SelectionToolbarAction]）即可，两类宿主都用它：
/// - 走 Flutter 文本选择的场景（`SelectionArea` / `SelectableRegion` 的
///   `contextMenuBuilder`）——本组件被放进根 Overlay，局部坐标即全局坐标；
/// - 自有选区实现（`AppSelectableText`）——本组件被放进一个「负偏移对齐屏幕、
///   尺寸等于屏幕」的图层，局部坐标同样等于全局坐标，因此上下避让、溢出分页
///   全部照常工作，同时图层随正文滚动、被祖先 Scrollable 剪裁、在页面 Stack
///   中天然位于词典面板之下。
///
/// 为何用 [CupertinoTextSelectionToolbar] 而非 [AdaptiveTextSelectionToolbar]：
/// 后者在 macOS 桌面自适应为纵向下拉菜单；前者可稳定复用横向布局、竖分隔线、
/// 溢出分页与上下避让。外壳由本组件替换为无箭头圆角胶囊，保持简洁一致。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../common/anchored_action_bar.dart';

/// 选区操作条的单个动作项：文案 + 点击回调。
class SelectionToolbarAction extends AnchoredActionBarAction {
  const SelectionToolbarAction({
    required super.label,
    required super.onPressed,
  });
}

/// 选区气泡操作条。
///
/// - [anchors]：选区锚点，来自 `SelectableRegionState.contextMenuAnchors`；
/// - [actions]：动作项列表（如「复制」「问 AI」），按顺序横向排布、以竖线分隔。
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.anchors,
    required this.actions,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<SelectionToolbarAction> actions;

  /// 按「选区几何」计算锚点：操作条居中浮在选区上方，并保留 Flutter 默认间距。
  ///
  /// 不直接用 [SelectableRegionState.contextMenuAnchors]——后者在**右键**触发时返回
  /// 鼠标点击位置（导致气泡贴在点击处而非选区中间）；这里始终从选区端点几何算出，
  /// 桌面右键 / 移动长按均居中于选区上方。
  static TextSelectionToolbarAnchors anchorsForSelection(
    SelectableRegionState state,
  ) {
    final renderObject = state.context.findRenderObject();
    if (renderObject is! RenderBox) return state.contextMenuAnchors;
    return TextSelectionToolbarAnchors.fromSelection(
      renderBox: renderObject,
      startGlyphHeight: state.startGlyphHeight,
      endGlyphHeight: state.endGlyphHeight,
      selectionEndpoints: state.selectionEndpoints,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredActionBar(anchors: anchors, actions: actions);
  }
}
