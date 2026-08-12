/// 词典设置页面
///
/// 设置默认词典源（单选，列已启用源），并启用/禁用可选源
/// （本地/AI 不可禁用，置灰锁定；其它可开关）。被禁用的源不出现在查词切换器。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/dictionary/dictionary_registry.dart';
import '../providers/dictionary/dictionary_settings_provider.dart';
import '../providers/dictionary/visible_sources_provider.dart';
import '../providers/pronunciation/pronunciation_providers.dart';
import '../services/dictionary/dictionary_source.dart';
import '../services/download/download_failure.dart';
import '../theme/app_theme.dart';
import '../utils/file_size.dart';
import '../widgets/dictionary/dict_source_presentation.dart';

/// 词典设置页面
class DictionarySettingsScreen extends ConsumerWidget {
  const DictionarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final allSources = ref.watch(dictionarySourcesProvider);
    final visible = ref.watch(visibleDictionarySourcesProvider);
    final settings = ref.watch(dictionarySettingsNotifierProvider);
    final notifier = ref.read(dictionarySettingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dictionarySettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.s,
        ),
        children: [
          _SectionHeader(
            title: l10n.dictionaryDefault,
            description: l10n.dictionaryDefaultDescription,
          ),
          Card(
            child: Column(
              children: [
                for (final s in visible)
                  ListTile(
                    leading: _SourceIcon(source: s),
                    title: Text(dictSourceLabel(l10n, s.id)),
                    trailing: settings.defaultSourceId == s.id
                        ? Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                          )
                        : Icon(
                            Icons.circle_outlined,
                            color: theme.colorScheme.outlineVariant,
                          ),
                    onTap: () => notifier.setDefault(s.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          _SectionHeader(
            title: l10n.dictionarySources,
            description: l10n.dictionarySourcesDescription,
          ),
          Card(
            child: Column(
              children: [
                for (final s in allSources)
                  _SourceToggleTile(
                    source: s,
                    enabled: !settings.disabledIds.contains(s.id),
                    onChanged: (v) => notifier.setDisabled(s.id, !v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          _SectionHeader(
            title: l10n.pronunciationLibrary,
            description: l10n.pronunciationLibraryDescription,
          ),
          const _PronunciationLibraryTile(),
          const SizedBox(height: AppSpacing.s),
          _WebAdsNotice(text: l10n.dictionaryWebAdsNotice),
        ],
      ),
    );
  }
}

class _PronunciationLibraryTile extends ConsumerWidget {
  const _PronunciationLibraryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(pronunciationLibraryProvider);
    final notifier = ref.read(pronunciationLibraryProvider.notifier);
    final title = switch (state.status) {
      PronunciationLibraryStatus.notDownloaded =>
        l10n.pronunciationLibraryWaiting,
      PronunciationLibraryStatus.downloading =>
        l10n.pronunciationLibraryDownloading,
      PronunciationLibraryStatus.installing =>
        l10n.pronunciationLibraryInstalling,
      PronunciationLibraryStatus.ready => l10n.pronunciationLibraryReady(
        formatBytes(state.localSizeBytes),
      ),
      PronunciationLibraryStatus.failed => _failureLabel(l10n, state.failure),
    };
    final busy =
        state.status == PronunciationLibraryStatus.downloading ||
        state.status == PronunciationLibraryStatus.installing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (state.status == PronunciationLibraryStatus.downloading) ...[
              const SizedBox(height: AppSpacing.s),
              LinearProgressIndicator(value: state.progress),
            ],
            if (!busy) ...[
              const SizedBox(height: AppSpacing.s),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: state.status == PronunciationLibraryStatus.ready
                      ? notifier.redownload
                      : notifier.retryDownload,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    state.status == PronunciationLibraryStatus.ready
                        ? l10n.redownload
                        : l10n.retry,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _failureLabel(AppLocalizations l10n, DownloadFailureKind? failure) =>
      switch (failure) {
        DownloadFailureKind.insufficientStorage => l10n.downloadErrorStorage,
        DownloadFailureKind.network => l10n.downloadErrorNetwork,
        DownloadFailureKind.verification => l10n.downloadErrorCorrupted,
        DownloadFailureKind.unknown || null => l10n.pronunciationLibraryFailed,
      };
}

/// 在线词典广告提醒：在线源为第三方网站，可能自带广告，与 Echo Loop 无关。
class _WebAdsNotice extends StatelessWidget {
  final String text;
  const _WebAdsNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 词典源图标：用品牌色给图标本身着色，让各源在列表中可区分。
class _SourceIcon extends StatelessWidget {
  final DictionarySource source;
  const _SourceIcon({required this.source});

  @override
  Widget build(BuildContext context) {
    final color = dictSourceColor(Theme.of(context).colorScheme, source.id);
    return Icon(source.icon, color: color);
  }
}

/// 分组标题 + 说明
class _SectionHeader extends StatelessWidget {
  final String title;
  final String description;
  const _SectionHeader({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个源的启用/禁用项：可禁用 → Switch；不可禁用 → 锁定灰字
class _SourceToggleTile extends StatelessWidget {
  final DictionarySource source;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SourceToggleTile({
    required this.source,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final label = dictSourceLabel(l10n, source.id);
    final icon = _SourceIcon(source: source);

    if (!source.canBeDisabled) {
      return ListTile(
        leading: icon,
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              l10n.dictSourceAlwaysOn,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dictSourceCannotDisable(label))),
        ),
      );
    }

    return SwitchListTile(
      secondary: icon,
      title: Text(label),
      value: enabled,
      onChanged: onChanged,
    );
  }
}
