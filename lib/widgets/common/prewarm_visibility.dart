/// 为后台预热提供主 tab 与当前路由的统一可见性判断。
library;

import 'package:flutter/material.dart';

/// 主导航壳向保留状态的分支页面暴露当前激活 tab。
class MainTabVisibilityScope extends InheritedWidget {
  const MainTabVisibilityScope({
    super.key,
    required this.currentIndex,
    required this.rootRouteVisible,
    required super.child,
  });

  /// 当前 StatefulShellRoute 分支索引。
  final int currentIndex;

  /// MainShell 所在的 root route 是否未被全屏页面覆盖。
  final bool rootRouteVisible;

  /// 当前上下文是否位于指定主 tab。
  static bool isActive(BuildContext context, int index) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MainTabVisibilityScope>();
    return scope?.currentIndex == index;
  }

  /// 当前上下文是否同时位于指定主 tab，且未被 root Navigator 覆盖。
  static bool isVisible(BuildContext context, int index) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MainTabVisibilityScope>();
    return scope != null &&
        scope.currentIndex == index &&
        scope.rootRouteVisible;
  }

  @override
  bool updateShouldNotify(MainTabVisibilityScope oldWidget) =>
      oldWidget.currentIndex != currentIndex ||
      oldWidget.rootRouteVisible != rootRouteVisible;
}

/// 监听页面/路由的可见性变化，并在每次进入或离开时通知宿主。
///
/// [localActive] 用于页面内部 tab 或弹窗的额外门控；路由切换和
/// StatefulShellRoute 的主 tab 切换由祖先上下文自动处理。
class PrewarmVisibility extends StatefulWidget {
  const PrewarmVisibility({
    super.key,
    required this.child,
    required this.onChanged,
    this.mainTabIndex,
    this.localActive = true,
  });

  final Widget child;
  final ValueChanged<bool> onChanged;
  final int? mainTabIndex;
  final bool localActive;

  @override
  State<PrewarmVisibility> createState() => _PrewarmVisibilityState();
}

class _PrewarmVisibilityState extends State<PrewarmVisibility> {
  bool? _lastVisible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisibility();
  }

  @override
  void didUpdateWidget(PrewarmVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localActive != widget.localActive ||
        oldWidget.mainTabIndex != widget.mainTabIndex) {
      _syncVisibility();
    }
  }

  @override
  void dispose() {
    if (_lastVisible == true) widget.onChanged(false);
    super.dispose();
  }

  void _syncVisibility() {
    final route = ModalRoute.of(context);
    // PopupRoute（底部弹窗 / Dialog）属于当前页面的交互层，打开音色选择器
    // 时不能把设置页误判为离开；普通 MaterialPageRoute 仍会停止后台预热。
    final routeVisible =
        route == null || route.isCurrent || route is PopupRoute<Object?>;
    final scope = context
        .dependOnInheritedWidgetOfExactType<MainTabVisibilityScope>();
    final rootRouteVisible = scope?.rootRouteVisible ?? true;
    final mainTabIndex = widget.mainTabIndex;
    final tabVisible =
        mainTabIndex == null ||
        MainTabVisibilityScope.isActive(context, mainTabIndex);
    final visible =
        widget.localActive && rootRouteVisible && routeVisible && tabVisible;
    if (_lastVisible == visible) return;
    _lastVisible = visible;
    widget.onChanged(visible);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
