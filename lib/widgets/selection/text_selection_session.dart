/// 选区会话（L1）：选区状态的唯一真相源
///
/// 这一层存在的理由：Flutter 的两个官方选区机制都在**失焦时清空选区**
/// （`material/selectable_text.dart` 的 `_handleFocusChanged`、
/// `widgets/selectable_region.dart` 的 `_handleFocusChanged`），且
/// `SelectableText` 还会在 `textSpan` 变化时重建 controller 让选区归零。而
/// 「选中一段文字 → 在页面内面板里查词/切源/收藏 → 选区必须还在」这个需求与
/// 上述契约直接冲突。把选区所有权收到这里，就不需要任何反向投影。
///
/// 本层**不含焦点概念**，也不含几何：
/// - 只存字符区间 + 内容身份，几何一律由 L3 按当前布局现算（字号、旋屏、
///   行高、重排都不会让状态失效）；
/// - 恢复前必须校验内容身份（[matchesContent]），内容变了就结束会话，
///   不按旧字符偏移盲目恢复。
library;

import 'dart:ui';

/// 选区会话阶段。
///
/// 拆出 [selecting] 是因为「正在选」与「选完了」的呈现规则不同：拖动期间要显示
/// 放大镜、藏掉操作条、且不提交查询；松手后才显示操作条并提交。Flutter 自身也
/// 有同类区分（`SelectableRegionSelectionStatus` 的 changing / finalized）。
enum TextSelectionPhase {
  /// 无选区。
  idle,

  /// 长按或拖手柄进行中（选区随手指变化，尚未提交）。
  selecting,

  /// 选区已确认（显示手柄与操作条，已提交查询）。
  active,
}

/// 单个内容的选区会话状态机。
///
/// 纯状态容器，不持有 widget、不发通知：拥有它的组件在改动前后自行 setState。
class TextSelectionSession {
  TextSelectionPhase _phase = TextSelectionPhase.idle;
  TextRange? _range;
  String? _contentIdentity;

  /// 当前阶段。
  TextSelectionPhase get phase => _phase;

  /// 当前选区字符区间；[TextSelectionPhase.idle] 时为 null。
  TextRange? get range => _range;

  /// 建立会话时的内容身份。
  String? get contentIdentity => _contentIdentity;

  /// 是否有有效选区（非折叠）。
  bool get hasSelection {
    final range = _range;
    return range != null && range.isValid && !range.isCollapsed;
  }

  /// 是否处于「选区已确认」阶段。
  bool get isActive => _phase == TextSelectionPhase.active && hasSelection;

  /// 是否处于「正在选」阶段。
  bool get isSelecting => _phase == TextSelectionPhase.selecting;

  /// 点词：直接确认选区（无拖动过程）。
  ///
  /// [range] 折叠或无效时等价于 [end]。
  void activate(TextRange range, String contentIdentity) {
    if (!range.isValid || range.isCollapsed) {
      end();
      return;
    }
    _range = range;
    _contentIdentity = contentIdentity;
    _phase = TextSelectionPhase.active;
  }

  /// 开始拖动（长按建立选区或抓住手柄）。
  void beginSelecting(TextRange range, String contentIdentity) {
    if (!range.isValid || range.isCollapsed) return;
    _range = range;
    _contentIdentity = contentIdentity;
    _phase = TextSelectionPhase.selecting;
  }

  /// 拖动中更新选区；不在 [TextSelectionPhase.selecting] 阶段则忽略。
  void updateSelecting(TextRange range) {
    if (_phase != TextSelectionPhase.selecting) return;
    if (!range.isValid || range.isCollapsed) return;
    _range = range;
  }

  /// 松手：把选区提交为已确认，返回最终区间。
  ///
  /// 未处于拖动阶段返回 null（调用方据此判断「这次松手不该触发查询」）。
  TextRange? commitSelecting() {
    if (_phase != TextSelectionPhase.selecting) return null;
    final range = _range;
    if (range == null || !range.isValid || range.isCollapsed) {
      end();
      return null;
    }
    _phase = TextSelectionPhase.active;
    return range;
  }

  /// 拖动被取消：回到上一个确认态（选区保留）或结束会话。
  void cancelSelecting() {
    if (_phase != TextSelectionPhase.selecting) return;
    _phase = hasSelection ? TextSelectionPhase.active : TextSelectionPhase.idle;
    if (_phase == TextSelectionPhase.idle) end();
  }

  /// 结束会话（显式关闭、点别处、换句、内容失效）。
  void end() {
    _phase = TextSelectionPhase.idle;
    _range = null;
    _contentIdentity = null;
  }

  /// 内容身份是否仍与建立会话时一致。
  bool matchesContent(String contentIdentity) =>
      _contentIdentity == null || _contentIdentity == contentIdentity;

  /// 内容变了就结束会话（不按旧字符偏移盲目恢复）。返回是否发生了结束。
  bool endIfContentChanged(String contentIdentity) {
    if (_phase == TextSelectionPhase.idle) return false;
    if (matchesContent(contentIdentity)) return false;
    end();
    return true;
  }
}
