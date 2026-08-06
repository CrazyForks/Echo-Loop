/// 意群文字快捷操作工具条。
library;

import 'package:flutter/material.dart';

import '../common/anchored_action_bar.dart';
import '../selection/selection_toolbar.dart';

/// 样式与文本选区操作条一致的意群操作条。
class SenseGroupActionBar extends StatelessWidget {
  const SenseGroupActionBar({
    super.key,
    required this.anchors,
    required this.actions,
  });

  final TextSelectionToolbarAnchors anchors;

  final List<SelectionToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    return AnchoredActionBar(anchors: anchors, actions: actions);
  }
}
