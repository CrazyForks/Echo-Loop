/// 官方合集 catalog 的客户端模型。
///
/// 与后端 `apps/app/lib/collections/dto.ts` 中的 `CatalogResponseDto` /
/// `CatalogCollectionDto` / `CatalogAudioDto` 一一对应。任何字段变更
/// 必须两端同步。
library;

/// catalog 内单条音频的元信息（不含 audioUrl / 字幕，下载时按需另拉）。
class CatalogAudio {
  final String id;
  final String title;
  final int durationSec;
  final int sortOrder;
  final String sha256;

  /// 原始发布/播出日期（后端运营录入，如 VOA 某期播出日期）；
  /// 未录入时为 null。后端返回 `yyyy-mm-dd` 字符串。
  final DateTime? originalDate;

  const CatalogAudio({
    required this.id,
    required this.title,
    required this.durationSec,
    required this.sortOrder,
    required this.sha256,
    this.originalDate,
  });

  factory CatalogAudio.fromJson(Map<String, dynamic> json) {
    final rawDate = json['originalDate'] as String?;
    return CatalogAudio(
      id: json['id'] as String,
      title: json['title'] as String,
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String,
      originalDate: rawDate == null ? null : DateTime.parse(rawDate),
    );
  }
}

/// catalog 内单个合集（含完整音频列表，按 sortOrder asc）。
class CatalogCollection {
  final String id;
  final String name;
  final String? description;
  final String? coverUrl;
  final DateTime publishedAt;
  final List<CatalogAudio> audios;

  const CatalogCollection({
    required this.id,
    required this.name,
    required this.description,
    required this.coverUrl,
    required this.publishedAt,
    required this.audios,
  });

  factory CatalogCollection.fromJson(Map<String, dynamic> json) {
    final rawAudios = (json['audios'] as List? ?? const []);
    return CatalogCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      coverUrl: json['coverUrl'] as String?,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      audios: rawAudios
          .map((e) => CatalogAudio.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// catalog 内单个精选 Podcast。
///
/// 后端 `podcastCatalogs` 当前返回扁平列表；客户端只把它作为发现页
/// 预览入口。真正订阅后仍使用本地 `CollectionSource.podcast`。
class CatalogPodcast {
  final String id;
  final String applePodcastUrl;
  final String rssUrl;
  final String? imageUrl;
  final String title;
  final String? description;

  const CatalogPodcast({
    required this.id,
    required this.applePodcastUrl,
    required this.rssUrl,
    required this.imageUrl,
    required this.title,
    required this.description,
  });

  factory CatalogPodcast.fromJson(Map<String, dynamic> json) {
    return CatalogPodcast(
      id: json['id'] as String,
      applePodcastUrl: json['applePodcastUrl'] as String? ?? '',
      rssUrl: json['rssUrl'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
    );
  }

  /// 订阅时提交给通用 Podcast 导入流程的原始输入 URL。
  ///
  /// catalog 同时给出 Apple Podcasts 和 RSS 时，优先保留 Apple 链接作为
  /// `podcast_input_url`；RSS 由导入流程解析后写入 `podcast_feed_url`。
  String get subscriptionInputUrl {
    final appleUrl = applePodcastUrl.trim();
    if (appleUrl.isNotEmpty) return appleUrl;
    return rssUrl.trim();
  }
}

/// catalog 的本地内存快照。
///
/// `contentHash` 用于 `OfficialCatalogService.refresh` 的 sha256 比对：
/// 后端响应 body 的 hash 与上次缓存一致即跳过文件重写 + 后续 sync diff。
/// `fetchedAt` 用于 catalog 普通刷新节流判断。
class CatalogSnapshot {
  final List<CatalogCollection> collections;
  final List<CatalogPodcast> podcastCatalogs;
  final String contentHash;
  final DateTime fetchedAt;

  const CatalogSnapshot({
    required this.collections,
    this.podcastCatalogs = const [],
    required this.contentHash,
    required this.fetchedAt,
  });
}
