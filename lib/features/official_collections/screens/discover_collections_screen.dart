import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../auth/sign_in_required_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/collection_provider.dart';
import '../../../router/app_router.dart';
import '../../../services/app_logger.dart';
import '../data/official_catalog_service.dart';
import '../data/trigger_official_sync.dart';
import '../models/catalog.dart';
import '../providers/discover_collections_provider.dart';
import '../providers/discover_podcasts_provider.dart';
import '../providers/official_enrollment_provider.dart';
import '../widgets/official_collection_card.dart';

const _logTag = 'DiscoverScreen';
const _podcastEntryIconAsset = 'assets/icon/apple-podcasts.svg';

/// 发现官方合集页。
///
/// 数据来源：本地 catalog 缓存（`cachedCatalogProvider`）。零网络。
///
/// 三态显式渲染：
/// - catalog 未初始化（首次安装等）→ loading
/// - catalog 已初始化但 collections 空 → empty
/// - catalog 有 collections → list + RefreshIndicator
///
/// 触发同步：
/// - initState → 强制 fire-and-forget syncAll；先展示缓存，更新后刷新页面
/// - 下拉刷新 → await syncAll(force: true)
/// - 不在此处单独触发任何 API 请求
class DiscoverCollectionsScreen extends ConsumerStatefulWidget {
  const DiscoverCollectionsScreen({super.key});

  @override
  ConsumerState<DiscoverCollectionsScreen> createState() =>
      _DiscoverCollectionsScreenState();
}

class _DiscoverCollectionsScreenState
    extends ConsumerState<DiscoverCollectionsScreen> {
  /// 当前正在 enroll 的 remoteId（让卡片 + 按钮转 spinner）
  final Set<String> _enrolling = <String>{};

  @override
  void initState() {
    super.initState();
    // 先由缓存立即渲染页面，再在后台强制拉取最新 catalog。
    // inflight 防重入保证不会和其它入口并发发起重复请求。
    AppLogger.log(_logTag, 'initState: triggering syncAll(force=true)');
    unawaited(_syncCatalog(force: true));
  }

  /// 触发全局唯一同步；helper 内部处理 outcome=updated 后的
  /// loadLibrary + loadCollections + invalidate catalog。
  Future<CatalogRefreshOutcome?> _syncCatalog({bool force = false}) =>
      triggerOfficialSync(ref, force: force);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final collections = ref.watch(discoverCollectionsProvider);
    final podcasts = ref.watch(discoverPodcastsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.discoverOfficialCollections)),
      body: _buildBody(collections, podcasts, l10n),
    );
  }

  Widget _buildBody(
    List<CatalogCollection>? collections,
    List<CatalogPodcast>? podcasts,
    AppLocalizations l10n,
  ) {
    // null = catalog 未初始化 → loading
    if (collections == null || podcasts == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // empty = 已初始化但无合集 → empty 状态（仍允许下拉刷新）
    return RefreshIndicator(
      onRefresh: () async {
        final outcome = await _syncCatalog(force: true);
        if (!mounted) return;
        if (outcome is CatalogUnchanged) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.discoverEmpty == '' ? '' : '已是最新')),
          );
        } else if (outcome is CatalogFailed) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.discoverLoadFailed)));
        }
      },
      child: collections.isEmpty && podcasts.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: _EmptyState(message: l10n.discoverEmpty),
                ),
              ],
            )
          : _buildList(collections, podcasts),
    );
  }

  Widget _buildList(
    List<CatalogCollection> items,
    List<CatalogPodcast> podcasts,
  ) {
    final collectionState = ref.watch(collectionListProvider);
    final enrolledRemoteIds = {
      for (final c in collectionState.collections)
        if (c.isOfficial && c.remoteId != null) c.remoteId!,
    };
    final remoteIdToLocalId = {
      for (final c in collectionState.collections)
        if (c.isOfficial && c.remoteId != null) c.remoteId!: c.id,
    };
    AppLogger.log(
      _logTag,
      'build list: catalog=${items.length}, enrolled=${enrolledRemoteIds.length}',
    );

    final hasPodcastEntry = podcasts.isNotEmpty;
    return ListView.builder(
      itemCount: items.length + (hasPodcastEntry ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasPodcastEntry && index == 0) {
          return _PodcastDiscoverEntry(
            onTap: () => context.push(AppRoutes.podcastSubscribe),
          );
        }
        final item = items[index - (hasPodcastEntry ? 1 : 0)];
        final enrolled = enrolledRemoteIds.contains(item.id);
        final enrolling = _enrolling.contains(item.id);
        return OfficialCollectionCard(
          item: item,
          enrolled: enrolled,
          enrolling: enrolling,
          onOpenDetail: () => context.push('/discover/${item.id}'),
          onEnroll: () => _handleEnroll(item),
          onGoLearn: () {
            final localId = remoteIdToLocalId[item.id];
            if (localId != null) {
              // 用 go 不用 push：/discover 在 root navigator，
              // /collections/xxx 在 shell branch。跨 navigator push
              // 会触发 go_router 17 + Flutter 3.24+ 的重复 page key assertion。
              context.go(AppRoutes.collectionDetail(localId));
            }
          },
        );
      },
    );
  }

  Future<void> _handleEnroll(CatalogCollection item) async {
    final l10n = AppLocalizations.of(context)!;
    final canEnroll = await ensureSignedInForAction(
      context: context,
      ref: ref,
      title: l10n.officialCollectionSignInRequiredTitle,
      message: l10n.officialCollectionSignInRequiredMessage,
    );
    if (!mounted || !canEnroll) return;

    final messenger = ScaffoldMessenger.of(context);
    AppLogger.log(
      _logTag,
      'tap enroll remoteId=${item.id} name="${item.name}"',
    );
    setState(() => _enrolling.add(item.id));
    try {
      final result = await ref
          .read(officialEnrollmentProvider.notifier)
          .enroll(item.id);
      AppLogger.log(
        _logTag,
        'enroll returned localId=${result.localCollectionId} '
        'createdNew=${result.createdNew}',
      );
      if (!mounted) return;
      if (result.createdNew) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.enrollSucceeded)));
      }
    } catch (e) {
      AppLogger.log(_logTag, 'enroll threw: $e');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.enrollFailed)));
    } finally {
      if (mounted) {
        setState(() => _enrolling.remove(item.id));
      }
    }
  }
}

class _PodcastDiscoverEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _PodcastDiscoverEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const _PodcastEntryImage(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.discoverPodcastEntryTitle,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PodcastEntryImage extends StatelessWidget {
  const _PodcastEntryImage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.secondaryContainer,
      ),
      child: Icon(
        Icons.podcasts_rounded,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 56,
        child: SvgPicture.asset(
          _podcastEntryIconAsset,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => placeholder,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.explore_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
