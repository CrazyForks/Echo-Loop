/// 书签标记行组件
///
/// 显示难句/收藏标记状态，点击切换。
/// 用于精听、难句补练、难句跟读和收藏复习页面。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'tappable_wrapper.dart';

/// 书签标记行
///
/// 右对齐的文字 + 书签图标，点击切换标记状态。
/// [isAutoMarked] 为 true 时显示"自动标记"文案（精听模式特有）。
class BookmarkToggleRow extends StatelessWidget {
  /// 是否已标记为难句/收藏
  final bool isDifficult;

  /// 是否为自动标记（精听模式中"看不懂"自动触发）
  final bool isAutoMarked;

  /// 点击切换回调
  final VoidCallback onTap;

  const BookmarkToggleRow({
    super.key,
    required this.isDifficult,
    this.isAutoMarked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final labelText = isDifficult
        ? (isAutoMarked
              ? l10n.intensiveListenAutoMarkedDifficult
              : l10n.intensiveListenMarkedDifficult)
        : l10n.intensiveListenNotDifficult;

    return TappableWrapper(
      onTap: onTap,
      feedbackType: TapFeedback.opacity,
      pressedOpacity: 0.4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              labelText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            isDifficult ? Icons.bookmark : Icons.bookmark_border,
            color: isDifficult ? Colors.amber : Colors.grey,
            size: 18,
          ),
        ],
      ),
    );
  }
}
