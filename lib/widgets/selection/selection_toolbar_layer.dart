/// 选区操作条的页面级挂载点（L2）
///
/// **为什么不能挂在正文自己的 Stack 里**：操作条通常要画在选区上方/下方，会溢出
/// 正文的 render box；而「跳过自身 size 剪裁的 Stack」只解决自身那一层，**祖先
/// 仍然按各自的 box 剪裁命中测试**，于是溢出部分点不动（单行句子的 box 只有约
/// 26dp 高，46dp 的操作条必然溢出）。
///
/// **为什么也不挂根 Overlay**：那会让操作条盖在页面内的词典面板之上，遮挡与滚动
/// 跟随都要手算几何——正是 2026-07-29 那批补丁的来源。
///
/// 所以由页面级宿主（`DictionaryPanelHost`）在自己的 Stack 里渲染，层序为
/// `正文 → 关面板屏障 → 操作条 → 面板`：点操作条不会被屏障吸收，面板天然遮住
/// 操作条，且不需要任何遮挡计算。内容组件只负责把「锚点 + 动作」推过来
/// （[SelectionToolbarRequest]），锚点用**全局坐标**，由宿主换算到自己的坐标系。
library;

import 'package:flutter/material.dart';

import 'selection_toolbar.dart';

/// 一次操作条挂载请求。
@immutable
class SelectionToolbarRequest {
  const SelectionToolbarRequest({
    required this.owner,
    required this.globalAnchors,
    required this.actions,
  });

  /// 发起者（与查词 owner 同一个对象）：宿主据此避免误清别人的操作条。
  final Object owner;

  /// 选区锚点，**全局坐标**（上方锚点 + 下方锚点，用于空间不足时翻面）。
  final TextSelectionToolbarAnchors globalAnchors;

  /// 动作项。空列表表示不显示。
  final List<SelectionToolbarAction> actions;

  @override
  bool operator ==(Object other) =>
      other is SelectionToolbarRequest &&
      identical(other.owner, owner) &&
      other.globalAnchors.primaryAnchor == globalAnchors.primaryAnchor &&
      other.globalAnchors.secondaryAnchor == globalAnchors.secondaryAnchor &&
      _sameActions(other.actions, actions);

  @override
  int get hashCode => Object.hash(
    identityHashCode(owner),
    globalAnchors.primaryAnchor,
    globalAnchors.secondaryAnchor,
    Object.hashAll(actions.map((a) => a.label)),
  );

  /// 由选区几何组装请求（锚点为全局坐标）。
  ///
  /// 用 [TextSelectionToolbarAnchors.fromSelection]：它内部按 `localToGlobal`
  /// 换算，返回的就是全局坐标，正好是宿主需要的输入。
  static SelectionToolbarRequest forSelection({
    required Object owner,
    required RenderBox content,
    required Rect startAnchor,
    required Rect endAnchor,
    required List<SelectionToolbarAction> actions,
  }) {
    return SelectionToolbarRequest(
      owner: owner,
      globalAnchors: TextSelectionToolbarAnchors.fromSelection(
        renderBox: content,
        startGlyphHeight: startAnchor.height,
        endGlyphHeight: endAnchor.height,
        selectionEndpoints: [
          TextSelectionPoint(
            Offset(startAnchor.left, startAnchor.bottom),
            TextDirection.ltr,
          ),
          TextSelectionPoint(
            Offset(endAnchor.right, endAnchor.bottom),
            TextDirection.ltr,
          ),
        ],
      ),
      actions: actions,
    );
  }

  static bool _sameActions(
    List<SelectionToolbarAction> a,
    List<SelectionToolbarAction> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label) return false;
    }
    return true;
  }
}

/// 渲染操作条的页面级图层。
///
/// 锚点必须是**本层（= 宿主 Stack）局部坐标**：由宿主在自己的 build 里用它已布局
/// 的 render box 换算（本层自己在首次 build 时 `findRenderObject()` 还是 null，
/// 不能就地换算）。
class SelectionToolbarLayer extends StatelessWidget {
  const SelectionToolbarLayer({
    super.key,
    required this.anchors,
    required this.actions,
  });

  /// 宿主 Stack 局部坐标下的选区锚点。
  final TextSelectionToolbarAnchors anchors;

  final List<SelectionToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return SelectionToolbar(anchors: anchors, actions: actions);
  }
}
