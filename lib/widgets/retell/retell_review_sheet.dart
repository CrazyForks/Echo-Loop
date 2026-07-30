/// 流式展示复述 AI 评测结果的下部弹窗。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/retell_review_evaluation.dart';
import '../../providers/retell_review_evaluation_provider.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_theme.dart';

/// 打开并持续订阅当前录音 attempt 的流式评测结果。
Future<void> showRetellReviewSheet(
  BuildContext context, {
  required String recordingPath,
  required AudioPlaybackService playbackService,
  required Future<void> Function() onBeforePlayback,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => _RetellReviewSheet(
    recordingPath: recordingPath,
    playbackService: playbackService,
    onBeforePlayback: onBeforePlayback,
  ),
);

class _RetellReviewSheet extends ConsumerWidget {
  final String recordingPath;
  final AudioPlaybackService playbackService;
  final Future<void> Function() onBeforePlayback;

  const _RetellReviewSheet({
    required this.recordingPath,
    required this.playbackService,
    required this.onBeforePlayback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(retellReviewEvaluationProvider);
    final evaluation = state.evaluation;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.s,
            AppSpacing.l,
            AppSpacing.l,
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                l10n.retellAiReviewTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.m),
              Expanded(
                child: state.phase == RetellReviewEvaluationPhase.failed
                    ? Center(
                        child: Text(
                          l10n.retellAiReviewError,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : evaluation == null
                    ? const Center(child: CircularProgressIndicator())
                    : _ReviewContent(
                        evaluation: evaluation,
                        recordingPath: recordingPath,
                        playbackService: playbackService,
                        onBeforePlayback: onBeforePlayback,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewContent extends StatelessWidget {
  final RetellReviewEvaluation evaluation;
  final String recordingPath;
  final AudioPlaybackService playbackService;
  final Future<void> Function() onBeforePlayback;

  const _ReviewContent({
    required this.evaluation,
    required this.recordingPath,
    required this.playbackService,
    required this.onBeforePlayback,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      children: [
        _RatingCard(
          label: _ratingLabel(l10n, evaluation.rating),
          summaryLabel: l10n.retellAiReviewSummary,
          summary: evaluation.summary,
        ),
        if (evaluation.transcript.isNotEmpty)
          _Section(
            title: l10n.retellAiReviewTranscript,
            trailing: _ReviewRecordingButton(
              recordingPath: recordingPath,
              playbackService: playbackService,
              onBeforePlayback: onBeforePlayback,
            ),
            children: [_TextCard(text: evaluation.transcript)],
          ),
        if (evaluation.strengths.isNotEmpty)
          _Section(
            title: l10n.retellAiReviewStrengths,
            children: [
              for (final item in evaluation.strengths)
                _TextCard(text: item.point, detail: item.evidence),
            ],
          ),
        if (evaluation.coveredKeyPoints.isNotEmpty)
          _Section(
            title: l10n.retellAiReviewCovered,
            children: [
              for (final item in evaluation.coveredKeyPoints)
                _TextCard(text: item.keyPoint, detail: item.evidence),
            ],
          ),
        if (evaluation.missedKeyPoints.isNotEmpty)
          _Section(
            title: l10n.retellAiReviewMissed,
            children: [
              for (final item in evaluation.missedKeyPoints)
                _TextCard(text: item.keyPoint, detail: item.explanation),
            ],
          ),
        if (evaluation.improvements.isNotEmpty)
          _Section(
            title: l10n.retellAiReviewImprovements,
            children: [
              for (final item in evaluation.improvements)
                _TextCard(
                  text: item.issue,
                  detail: '${item.evidence}\n${item.suggestion}',
                ),
            ],
          ),
        if (evaluation.grammarErrors.isNotEmpty)
          _Section(
            title: l10n.retellAiReviewGrammar,
            children: [
              for (final item in evaluation.grammarErrors)
                _TextCard(
                  text: item.original,
                  detail: '${item.correction}\n${item.explanation}',
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.l),
      ],
    );
  }

  String _ratingLabel(AppLocalizations l10n, RetellReviewRating rating) =>
      switch (rating) {
        RetellReviewRating.keepGoing => l10n.listenAndRepeatRatingKeepGoing,
        RetellReviewRating.fair => l10n.listenAndRepeatRatingFair,
        RetellReviewRating.good => l10n.listenAndRepeatRatingGood,
        RetellReviewRating.excellent => l10n.listenAndRepeatRatingExcellent,
        RetellReviewRating.perfect => l10n.listenAndRepeatRatingPerfect,
      };
}

class _RatingCard extends StatelessWidget {
  final String label;
  final String summaryLabel;
  final String summary;

  const _RatingCard({
    required this.label,
    required this.summaryLabel,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.m),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            summaryLabel,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(summary),
        ],
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _Section({required this.title, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        ...children,
      ],
    ),
  );
}

/// 弹窗内复用页面级播放服务，用户可在查看转录时直接试听本次录音。
class _ReviewRecordingButton extends StatefulWidget {
  final String recordingPath;
  final AudioPlaybackService playbackService;
  final Future<void> Function() onBeforePlayback;

  const _ReviewRecordingButton({
    required this.recordingPath,
    required this.playbackService,
    required this.onBeforePlayback,
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
    return IconButton(
      tooltip: _isPlaying
          ? l10n.retellAiReviewStopRecording
          : l10n.retellAiReviewPlayRecording,
      onPressed: _handleTap,
      icon: Icon(_isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
    );
  }
}

class _TextCard extends StatelessWidget {
  final String text;
  final String? detail;

  const _TextCard({required this.text, this.detail});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: AppSpacing.s),
    padding: const EdgeInsets.all(AppSpacing.m),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (detail != null && detail!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}
