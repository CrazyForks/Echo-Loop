/// 当前用户的地区判定状态。
///
/// 此状态只缓存于当前 App 进程：冷启动和回到前台时会重新确认，避免把商店区、
/// 系统地区或服务端推断出的旧结果长期写入本地偏好。
library;

/// 参与中国用户判定的证据来源。
enum UserRegionEvidence { storefront, deviceRegion, clientConfig }

/// 单个地区策略的执行状态。
enum UserRegionSourceStatus { pending, available, skipped, failed }

/// 单个地区策略的最新结果。
class UserRegionSourceResult {
  const UserRegionSourceResult({required this.status, this.countryCode});

  const UserRegionSourceResult.pending()
    : status = UserRegionSourceStatus.pending,
      countryCode = null;

  const UserRegionSourceResult.skipped()
    : status = UserRegionSourceStatus.skipped,
      countryCode = null;

  const UserRegionSourceResult.failed()
    : status = UserRegionSourceStatus.failed,
      countryCode = null;

  final UserRegionSourceStatus status;
  final String? countryCode;

  /// 此来源是否明确表明用户属于中国。
  bool get isChina => _isChinaCountryCode(countryCode);

  @override
  String toString() => '${status.name}:${countryCode ?? "unknown"}';
}

/// 地区判定的进程内单一真相源。
class UserRegionState {
  const UserRegionState({
    required this.isChinaUser,
    required this.storefront,
    required this.deviceRegion,
    required this.clientConfig,
    required this.matchedSources,
    required this.isRefreshing,
    this.lastRefreshedAt,
  });

  /// 以所有已知证据生成一致的最终结论。
  factory UserRegionState.resolve({
    required UserRegionSourceResult storefront,
    required UserRegionSourceResult deviceRegion,
    required UserRegionSourceResult clientConfig,
    required bool isRefreshing,
    DateTime? lastRefreshedAt,
  }) {
    final sources = <UserRegionEvidence>[
      if (storefront.isChina) UserRegionEvidence.storefront,
      if (deviceRegion.isChina) UserRegionEvidence.deviceRegion,
      if (clientConfig.isChina) UserRegionEvidence.clientConfig,
    ];
    return UserRegionState(
      isChinaUser: sources.isNotEmpty,
      storefront: storefront,
      deviceRegion: deviceRegion,
      clientConfig: clientConfig,
      matchedSources: List.unmodifiable(sources),
      isRefreshing: isRefreshing,
      lastRefreshedAt: lastRefreshedAt,
    );
  }

  final bool isChinaUser;
  final UserRegionSourceResult storefront;
  final UserRegionSourceResult deviceRegion;
  final UserRegionSourceResult clientConfig;
  final List<UserRegionEvidence> matchedSources;
  final bool isRefreshing;
  final DateTime? lastRefreshedAt;

  UserRegionState copyWith({
    UserRegionSourceResult? storefront,
    UserRegionSourceResult? deviceRegion,
    UserRegionSourceResult? clientConfig,
    bool? isRefreshing,
    DateTime? lastRefreshedAt,
  }) {
    return UserRegionState.resolve(
      storefront: storefront ?? this.storefront,
      deviceRegion: deviceRegion ?? this.deviceRegion,
      clientConfig: clientConfig ?? this.clientConfig,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
    );
  }
}

/// 由应用生命周期传入的刷新原因，供诊断日志区分启动和回前台。
enum UserRegionRefreshTrigger { startup, resume }

bool _isChinaCountryCode(String? countryCode) {
  final normalized = countryCode?.trim().toUpperCase();
  return normalized == 'CN' || normalized == 'CHN';
}
