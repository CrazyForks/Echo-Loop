/// 通用四档记忆评分栏。
library;

import 'package:flutter/material.dart';

import '../../memory_scheduler/domain/memory_rating.dart';
import '../../memory_scheduler/domain/memory_scheduler_results.dart';

/// 根据可用宽度自动使用单排或 2x2 的评分按钮。
class MemoryRatingBar extends StatelessWidget {
  const MemoryRatingBar({
    super.key,
    required this.previews,
    required this.onRating,
    this.enabled = true,
  });

  final MemoryRatingPreviewSet? previews;
  final ValueChanged<MemoryRating> onRating;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final buttons = MemoryRating.values
        .map((rating) {
          final preview = _previewFor(rating);
          return OutlinedButton(
            onPressed: enabled ? () => onRating(rating) : null,
            child: Text(
              '${_label(rating)}\n${_formatInterval(preview?.interval)}',
            ),
          );
        })
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth < 440;
        return GridView.count(
          crossAxisCount: twoColumns ? 2 : 4,
          shrinkWrap: true,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: twoColumns ? 2.2 : 1.4,
          physics: const NeverScrollableScrollPhysics(),
          children: buttons,
        );
      },
    );
  }

  MemoryRatingPreview? _previewFor(MemoryRating rating) {
    final set = previews;
    if (set == null) return null;
    return switch (rating) {
      MemoryRating.again => set.again,
      MemoryRating.hard => set.hard,
      MemoryRating.good => set.good,
      MemoryRating.easy => set.easy,
    };
  }

  String _label(MemoryRating rating) => switch (rating) {
    MemoryRating.again => 'Again',
    MemoryRating.hard => 'Hard',
    MemoryRating.good => 'Good',
    MemoryRating.easy => 'Easy',
  };

  String _formatInterval(Duration? interval) {
    if (interval == null) return '-';
    if (interval.inHours < 1) return '${interval.inMinutes} min';
    if (interval.inDays < 1) return '${interval.inHours} h';
    return '${interval.inDays} d';
  }
}
