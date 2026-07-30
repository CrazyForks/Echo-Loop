/// 选区操作条的挂载点抽象与通用宿主（L2）
///
/// 操作条**必须挂在页面级宿主**上（原因见 `selection_toolbar_layer.dart`）。
/// 项目里有两种宿主：
/// - 查词页面用 [DictionaryPanelHost]：层序为「正文 → 关面板屏障 → 操作条 → 面板」，
///   遮挡与可点性全由层序解决，因此它自己渲染操作条图层；
/// - 其它页面（如聊天载体）没有面板，用本文件的 [SelectionToolbarHost] 即可。
///
/// 两者都实现 [SelectionToolbarMount] 并通过 [SelectionToolbarScope] 暴露给子树，
/// 于是可选文本组件只认这一个接口，不关心自己被放进了哪种页面。
library;

import 'package:flutter/material.dart';

import 'selection_toolbar_layer.dart';

/// 操作条挂载点。
abstract interface class SelectionToolbarMount {
  /// 挂载/更新操作条（同一 owner 重复推送按相等性去重）。
  void showSelectionToolbar(SelectionToolbarRequest request);

  /// 收起操作条；仅 [owner] 能收起自己挂的那个。
  void hideSelectionToolbar(Object owner);
}

/// 向子树暴露操作条挂载点。
class SelectionToolbarScope extends InheritedWidget {
  const SelectionToolbarScope({
    super.key,
    required this.mount,
    required super.child,
  });

  final SelectionToolbarMount mount;

  /// 取最近的挂载点；**不建立依赖**（只在回调里用，不该引起重建）。
  static SelectionToolbarMount? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SelectionToolbarScope>()?.mount;

  @override
  bool updateShouldNotify(SelectionToolbarScope oldWidget) =>
      !identical(oldWidget.mount, mount);
}

/// 通用页面级操作条宿主：`Stack[ 正文, 操作条 ]`。
///
/// 用法：把页面（或 sheet）内容包一层。自身不含任何面板/屏障逻辑。
class SelectionToolbarHost extends StatefulWidget {
  const SelectionToolbarHost({super.key, required this.child});

  final Widget child;

  @override
  State<SelectionToolbarHost> createState() => SelectionToolbarHostState();
}

/// [SelectionToolbarHost] 的 state。
class SelectionToolbarHostState extends State<SelectionToolbarHost>
    implements SelectionToolbarMount {
  SelectionToolbarRequest? _request;

  @override
  void showSelectionToolbar(SelectionToolbarRequest request) {
    // 请求可能来自已卸载内容的延迟回调，宿主自身也可能正在销毁。
    if (!mounted || _request == request) return;
    setState(() => _request = request);
  }

  @override
  void hideSelectionToolbar(Object owner) {
    if (!mounted || !identical(_request?.owner, owner)) return;
    setState(() => _request = null);
  }

  /// 全局锚点 → 本宿主 Stack 的局部锚点。
  ///
  /// 换算必须在**宿主**里做：操作条图层自身首次 build 时 `findRenderObject()`
  /// 还是 null，无法就地换算。
  TextSelectionToolbarAnchors _toLocalAnchors(
    TextSelectionToolbarAnchors global,
  ) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return global;
    final secondary = global.secondaryAnchor;
    return TextSelectionToolbarAnchors(
      primaryAnchor: box.globalToLocal(global.primaryAnchor),
      secondaryAnchor: secondary == null ? null : box.globalToLocal(secondary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelectionToolbarScope(
      mount: this,
      child: Stack(
        children: [
          widget.child,
          if (_request case final request?)
            Positioned.fill(
              child: SelectionToolbarLayer(
                anchors: _toLocalAnchors(request.globalAnchors),
                actions: request.actions,
              ),
            ),
        ],
      ),
    );
  }
}
