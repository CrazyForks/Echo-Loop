import 'package:flutter/material.dart';

/// 应用内统一的分段选择器。
///
/// 仅负责统一选择器的视觉样式，选项和选中状态由调用方管理。
class AppSegmentedButton<T> extends StatelessWidget {
  /// 要展示的分段选项。
  final List<ButtonSegment<T>> segments;

  /// 当前选中的选项集合。
  final Set<T> selected;

  /// 用户切换选项后的回调。
  final ValueChanged<Set<T>> onSelectionChanged;

  /// 选择器的最小高度，默认保持复习统计页的标准高度。
  final double minimumHeight;

  /// 点击目标尺寸策略，默认保留 Material 的标准点击目标。
  ///
  /// 紧凑模式使用显式高度，此参数仅作用于 Flutter 原生实现。
  final MaterialTapTargetSize tapTargetSize;

  /// 可选的分段内容内边距；紧凑布局可传入零内边距。
  final EdgeInsetsGeometry? padding;

  const AppSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.minimumHeight = 44,
    this.tapTargetSize = MaterialTapTargetSize.padded,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = SegmentedButton<T>(
      showSelectedIcon: false,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.fromHeight(minimumHeight)),
        tapTargetSize: tapTargetSize,
        padding: padding == null ? null : WidgetStatePropertyAll(padding),
        visualDensity: VisualDensity.standard,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.colorScheme.primaryContainer;
          }
          return theme.colorScheme.surface;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      segments: segments,
      selected: selected,
      onSelectionChanged: onSelectionChanged,
    );

    if (minimumHeight >= 40) return button;

    // Flutter 的 SegmentedButton 内部将单个 segment 的最小高度固定为 40dp；
    // 紧凑场景使用独立的 30dp 外框，避免通过整体缩放压扁文字。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth < _CompactSegmentedButton.maxWidth
                  ? constraints.maxWidth
                  : _CompactSegmentedButton.maxWidth
            : _CompactSegmentedButton.maxWidth;
        return _CompactSegmentedButton<T>(
          width: width,
          height: minimumHeight,
          segments: segments,
          selected: selected,
          onSelectionChanged: onSelectionChanged,
          padding: padding,
          outlineColor: theme.colorScheme.outlineVariant,
          selectedColor: theme.colorScheme.primaryContainer,
          unselectedColor: theme.colorScheme.surface,
          disabledColor: theme.colorScheme.onSurface.withValues(alpha: 0.12),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          disabledTextStyle: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

/// 低于 Flutter 原生最小高度时使用的紧凑分段选择器。
class _CompactSegmentedButton<T> extends StatelessWidget {
  // 四个分段最大总宽控制在 200dp，避免选择器在学习卡片中横向铺满。
  static const maxWidth = 200.0;

  final double width;
  final double height;
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;
  final EdgeInsetsGeometry? padding;
  final Color outlineColor;
  final Color selectedColor;
  final Color unselectedColor;
  final Color disabledColor;
  final TextStyle? textStyle;
  final TextStyle? disabledTextStyle;

  const _CompactSegmentedButton({
    required this.width,
    required this.height,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    required this.padding,
    required this.outlineColor,
    required this.selectedColor,
    required this.unselectedColor,
    required this.disabledColor,
    required this.textStyle,
    required this.disabledTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                for (final (index, segment) in segments.indexed)
                  Expanded(
                    child: _buildSegment(index: index, segment: segment),
                  ),
              ],
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: outlineColor),
                  borderRadius: radius,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment({
    required int index,
    required ButtonSegment<T> segment,
  }) {
    final isSelected = selected.contains(segment.value);
    final label = _buildSegmentContent(segment);
    final backgroundColor = segment.enabled
        ? isSelected
              ? selectedColor
              : unselectedColor
        : disabledColor;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: index == 0
            ? null
            : Border(left: BorderSide(color: outlineColor)),
      ),
      child: Semantics(
        button: true,
        enabled: segment.enabled,
        selected: isSelected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: segment.enabled
                ? () {
                    if (!isSelected) onSelectionChanged({segment.value});
                  }
                : null,
            child: Center(
              child: Padding(
                padding: padding ?? EdgeInsets.zero,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: DefaultTextStyle.merge(
                    style: segment.enabled ? textStyle : disabledTextStyle,
                    child: label,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 保留 ButtonSegment 的图标和文字组合，避免紧凑实现与原生实现行为不一致。
  Widget _buildSegmentContent(ButtonSegment<T> segment) {
    if (segment.icon == null) {
      return segment.label ?? const SizedBox.shrink();
    }
    if (segment.label == null) return segment.icon!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [segment.icon!, const SizedBox(width: 4), segment.label!],
    );
  }
}
