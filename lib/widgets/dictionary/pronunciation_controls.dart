import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/pronunciation/pronunciation_clip.dart';
import '../../providers/pronunciation/pronunciation_providers.dart';

/// 单个本地发音图标，保持词典标题行原有紧凑布局。
class LocalPronunciationIconButton extends ConsumerWidget {
  const LocalPronunciationIconButton({
    super.key,
    required this.clip,
    required this.fallbackText,
  });

  final PronunciationClip clip;
  final String fallbackText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      pronunciationPlaybackProvider.select(
        (state) => state.playingKey == clip.playbackKey,
      ),
    );
    return IconButton(
      key: const Key('dict_single_local_pronunciation'),
      visualDensity: VisualDensity.compact,
      tooltip: AppLocalizations.of(context)!.pronunciationPlay,
      onPressed: () => ref
          .read(pronunciationPlaybackProvider.notifier)
          .play(clip, fallbackText: fallbackText),
      icon: Icon(
        Icons.volume_up,
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 多发音 badge 组；窄屏由 Wrap 自动换行。
class PronunciationBadgeGroup extends ConsumerWidget {
  const PronunciationBadgeGroup({
    super.key,
    required this.clips,
    required this.fallbackText,
  });

  final List<PronunciationClip> clips;
  final String fallbackText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playingKey = ref.watch(
      pronunciationPlaybackProvider.select((state) => state.playingKey),
    );
    return Wrap(
      key: const Key('dict_pronunciation_badges'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final clip in clips)
          ActionChip(
            key: ValueKey(clip.playbackKey),
            avatar: Icon(
              Icons.volume_up,
              size: 16,
              color: playingKey == clip.playbackKey
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            label: Text(
              _reasonLabel(AppLocalizations.of(context)!, clip.reason),
            ),
            onPressed: () => ref
                .read(pronunciationPlaybackProvider.notifier)
                .play(clip, fallbackText: fallbackText),
          ),
      ],
    );
  }
}

String _reasonLabel(AppLocalizations l10n, PronunciationReason? reason) =>
    switch (reason) {
      null => l10n.pronunciationStandard,
      PronunciationReason.adjective => l10n.pronunciationAdjective,
      PronunciationReason.noun => l10n.pronunciationNoun,
      PronunciationReason.nounAdjective => l10n.pronunciationNounAdjective,
      PronunciationReason.verb => l10n.pronunciationVerb,
      PronunciationReason.pastTense => l10n.pronunciationPastTense,
      PronunciationReason.presentTense => l10n.pronunciationPresentTense,
      PronunciationReason.interjection => l10n.pronunciationInterjection,
    };
