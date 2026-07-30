/// 越界命中 Stack（L2 支撑件）
///
/// 普通 `RenderBox.hitTest` 会在 `size.contains(position)` 处提前剪裁，于是悬在
/// 内容 bounds 之外的选区手柄（首行上方、末行下方、行首左侧）点不动。本 Stack
/// 跳过**自身**这一层剪裁，直接测试子节点。
///
/// 注意作用范围：只解决自身这一层。**祖先仍然按各自的 box 剪裁命中测试**，所以
/// 溢出较多的浮层（如选区操作条）不能靠它救——那类必须挂到页面级宿主上，
/// 见 `selection_toolbar_layer.dart`。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 不做自身 size 剪裁的 [Stack]。
class UnboundedHitStack extends Stack {
  const UnboundedHitStack({super.key, super.children})
    : super(clipBehavior: Clip.none);

  @override
  RenderStack createRenderObject(BuildContext context) =>
      _RenderUnboundedHitStack(
        textDirection: textDirection ?? Directionality.maybeOf(context),
        alignment: alignment,
        fit: fit,
        clipBehavior: clipBehavior,
      );
}

class _RenderUnboundedHitStack extends RenderStack {
  _RenderUnboundedHitStack({
    super.textDirection,
    super.alignment,
    super.fit,
    super.clipBehavior,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // 跳过 RenderBox 默认的 size.contains 剪裁，直接测试子节点。
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
