/// 复述 AI 评估报告正文。
///
/// 纯展示层：只根据一份（可能仍在流式增长的）[RetellReviewEvaluation] 快照渲染，
/// 不读 provider、不发起副作用。所有 section 按「字段是否已到达」逐个出现，
/// 半成品条目（要点文本为空、语法原句为空）直接跳过，避免流式过程中的空行闪烁。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/retell_review_evaluation.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_theme.dart';
import 'retell_review_rating_style.dart';

/// 评估报告正文（可滚动）。
class RetellReviewReport extends StatelessWidget {
  final RetellReviewEvaluation evaluation;

  /// 是否仍在接收增量帧；为 true 时底部显示「正在生成…」提示。
  final bool isStreaming;

  final String recordingPath;
  final AudioPlaybackService playbackService;
  final Future<void> Function() onBeforePlayback;

  const RetellReviewReport({
    super.key,
    required this.evaluation,
    required this.isStreaming,
    required this.recordingPath,
    required this.playbackService,
    required this.onBeforePlayback,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 增量协议下要点文本先于状态到达，文本为空的条目还没成形，先不渲染。
    final keyPoints = [
      for (final item in evaluation.keyPoints)
        if (item.keyPoint.isNotEmpty) item,
    ];
    final corrections = [
      for (final item in evaluation.corrections)
        if (item.transcript.isNotEmpty) item,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        _RatingHero(
          evaluation: evaluation,
          recordingPath: recordingPath,
          playbackService: playbackService,
          onBeforePlayback: onBeforePlayback,
        ),
        if (keyPoints.isNotEmpty) ...[
          _SectionLabel(
            title: l10n.retellAiReviewKeyPoints,
            trailing: _StatusTally(keyPoints: keyPoints),
          ),
          _KeyPointGroup(keyPoints: keyPoints),
        ],
        if (evaluation.suggestion.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.l),
          _SuggestionCallout(text: evaluation.suggestion),
        ],
        if (corrections.isNotEmpty) ...[
          _SectionLabel(title: l10n.retellAiReviewCorrections),
          for (final item in corrections) _CorrectionCard(correction: item),
        ],
        if (evaluation.transcript.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.l),
          _TranscriptExpander(transcript: evaluation.transcript),
        ],
        if (isStreaming) const _GeneratingPill(),
      ],
    );
  }
}

/// 顶部结论区：评级词 + 五档进度 + 总评 + 录音试听，按评级着色。
class _RatingHero extends StatelessWidget {
  final RetellReviewEvaluation evaluation;
  final String recordingPath;
  final AudioPlaybackService playbackService;
  final Future<void> Function() onBeforePlayback;

  const _RatingHero({
    required this.evaluation,
    required this.recordingPath,
    required this.playbackService,
    required this.onBeforePlayback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final visual = retellRatingVisual(context, l10n, evaluation.rating);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: visual.container,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visual.accent.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: visual.accent.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Icon(visual.icon, size: 22, color: visual.accent),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visual.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: visual.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),
                    _RatingPips(accent: visual.accent, level: visual.level),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              _ReviewRecordingButton(
                recordingPath: recordingPath,
                playbackService: playbackService,
                onBeforePlayback: onBeforePlayback,
                accent: visual.accent,
              ),
            ],
          ),
          if (evaluation.summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.m),
            Text(
              evaluation.summary,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// 五档评级进度块；评级未到达时全部为暗档。
class _RatingPips extends StatelessWidget {
  final Color accent;
  final int level;

  const _RatingPips({required this.accent, required this.level});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < retellRatingLevelCount; i++)
        Container(
          width: 20,
          height: 5,
          margin: EdgeInsets.only(
            right: i == retellRatingLevelCount - 1 ? 0 : 4,
          ),
          decoration: BoxDecoration(
            color: i < level ? accent : accent.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );
}

/// 小节标题，右侧可挂统计信息。
class _SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionLabel({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: AppSpacing.l,
      bottom: AppSpacing.s,
      left: AppSpacing.xs,
    ),
    child: Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.m),
          Expanded(child: trailing!),
        ],
      ],
    ),
  );
}

/// 按状态聚合的色点计数条，让整体覆盖情况一眼可读。
class _StatusTally extends StatelessWidget {
  final List<RetellReviewKeyPoint> keyPoints;

  const _StatusTally({required this.keyPoints});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final counts = <RetellReviewKeyPointStatus, int>{};
    for (final item in keyPoints) {
      final status = item.status;
      if (status != null) counts[status] = (counts[status] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.s + 2,
      runSpacing: AppSpacing.xs,
      children: [
        // 固定按 covered→partial→missed→distorted 顺序，避免逐帧到达时顺序跳动。
        for (final status in RetellReviewKeyPointStatus.values)
          if (counts[status] != null)
            _TallyItem(status: status, count: counts[status]!, l10n: l10n),
      ],
    );
  }
}

class _TallyItem extends StatelessWidget {
  final RetellReviewKeyPointStatus status;
  final int count;
  final AppLocalizations l10n;

  const _TallyItem({
    required this.status,
    required this.count,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final visual = retellKeyPointVisual(context, l10n, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: visual.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs + 1),
        Text(
          '$count ${visual.label}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 要点清单：单一分组容器 + 分隔线，避免一条一个描边卡片的碎片感。
class _KeyPointGroup extends StatelessWidget {
  final List<RetellReviewKeyPoint> keyPoints;

  const _KeyPointGroup({required this.keyPoints});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < keyPoints.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.m,
                endIndent: AppSpacing.m,
                color: colorScheme.outlineVariant.withValues(alpha: .45),
              ),
            _KeyPointRow(keyPoint: keyPoints[i]),
          ],
        ],
      ),
    );
  }
}

class _KeyPointRow extends StatelessWidget {
  final RetellReviewKeyPoint keyPoint;

  const _KeyPointRow({required this.keyPoint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final visual = retellKeyPointVisual(context, l10n, keyPoint.status);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(visual.icon, size: 18, color: visual.color),
          ),
          const SizedBox(width: AppSpacing.s + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  keyPoint.keyPoint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (keyPoint.feedback.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    keyPoint.feedback,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.45,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 唯一一条建议，用 callout 突出，和要点清单形成层级差。
class _SuggestionCallout extends StatelessWidget {
  final String text;

  const _SuggestionCallout({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_rounded,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.s + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.retellAiReviewSuggestion,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 表达纠错：「类别标签 → 原句 → 更正（成功色）→ 说明」四层对照。
///
/// 原句是否划掉由类别决定（见 [retellCorrectionTypeVisual]）：只有说错了的
/// 语法和用词才划掉，冗余/说法/衔接的原句本身不算错。
class _CorrectionCard extends StatelessWidget {
  final RetellReviewCorrection correction;

  const _CorrectionCard({required this.correction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final typeVisual = retellCorrectionTypeVisual(
      context,
      l10n,
      correction.type,
    );
    final correctionColor = retellCorrectionColor(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类别尚未到达时不占位，避免流式过程中标签闪现。
          if (typeVisual.label.isNotEmpty) ...[
            _CorrectionTypeChip(visual: typeVisual),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(
            correction.transcript,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
              color: typeVisual.color,
              decoration: typeVisual.strikeThrough
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationColor: typeVisual.color.withValues(alpha: .6),
            ),
          ),
          if (correction.correction.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: correctionColor,
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    correction.correction,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: correctionColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (correction.explanation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              correction.explanation,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 纠错类别标签，用类别色淡染的小胶囊。
class _CorrectionTypeChip extends StatelessWidget {
  final RetellCorrectionTypeVisual visual;

  const _CorrectionTypeChip({required this.visual});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s,
      vertical: AppSpacing.xs - 1,
    ),
    decoration: BoxDecoration(
      color: visual.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      visual.label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: visual.color,
      ),
    ),
  );
}

/// 转录原文默认收起：它最长、最不可操作，放在报告末尾按需展开。
class _TranscriptExpander extends StatelessWidget {
  final String transcript;

  const _TranscriptExpander({required this.transcript});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: theme.colorScheme.outlineVariant.withValues(alpha: .55),
      ),
    );
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        shape: shape,
        collapsedShape: shape,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        collapsedBackgroundColor: theme.colorScheme.surfaceContainerHighest,
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          0,
          AppSpacing.m,
          AppSpacing.m,
        ),
        leading: Icon(
          Icons.subject_rounded,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          l10n.retellAiReviewTranscript,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              transcript,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 流式未结束的提示，告诉用户后面还有内容会出现。
class _GeneratingPill extends StatelessWidget {
  const _GeneratingPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.l),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Text(
            AppLocalizations.of(context)!.retellAiReviewGenerating,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero 内复用页面级播放服务，用户可在看报告时直接试听本次录音。
class _ReviewRecordingButton extends StatefulWidget {
  final String recordingPath;
  final AudioPlaybackService playbackService;
  final Future<void> Function() onBeforePlayback;
  final Color accent;

  const _ReviewRecordingButton({
    required this.recordingPath,
    required this.playbackService,
    required this.onBeforePlayback,
    required this.accent,
  });

  @override
  State<_ReviewRecordingButton> createState() => _ReviewRecordingButtonState();
}

class _ReviewRecordingButtonState extends State<_ReviewRecordingButton> {
  StreamSubscription<bool>? _playingSubscription;
  var _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.playbackService.isPlaying;
    _playingSubscription = widget.playbackService.isPlayingStream.listen((
      value,
    ) {
      if (mounted) setState(() => _isPlaying = value);
    });
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isPlaying) {
      await widget.playbackService.stop();
      return;
    }
    await widget.onBeforePlayback();
    if (!mounted) return;
    await widget.playbackService.play(widget.recordingPath);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton.filled(
      tooltip: _isPlaying
          ? l10n.retellAiReviewStopRecording
          : l10n.retellAiReviewPlayRecording,
      onPressed: _handleTap,
      style: IconButton.styleFrom(
        backgroundColor: widget.accent,
        foregroundColor: Theme.of(context).colorScheme.surface,
      ),
      icon: Icon(_isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
    );
  }
}
