/// 百度网盘当前授权账户的公开资料。
library;

/// `xpan/nas?method=uinfo` 返回的账户资料。
class BaiduAccountProfile {
  /// 构造账户资料。
  const BaiduAccountProfile({
    required this.uk,
    this.baiduName,
    this.netdiskName,
    this.vipType,
    this.avatarUrl,
  });

  /// 百度网盘内部用户 ID。
  final int uk;

  /// 百度账号名。
  final String? baiduName;

  /// 百度网盘昵称。
  final String? netdiskName;

  /// 百度网盘会员类型：0 普通用户，1 VIP，2 SVIP。
  final int? vipType;

  /// 百度账户头像地址。
  final String? avatarUrl;

  /// 会员类型的可读名称；未知或缺失时返回 `unknown`。
  String get membershipLabel => switch (vipType) {
    0 => 'free',
    1 => 'vip',
    2 => 'svip',
    _ => 'unknown',
  };

  /// 从百度响应解析资料。
  factory BaiduAccountProfile.fromBaiduJson(Map<dynamic, dynamic> json) {
    final rawUk = json['uk'];
    final uk = rawUk is int
        ? rawUk
        : rawUk is num
        ? rawUk.toInt()
        : rawUk is String
        ? int.tryParse(rawUk)
        : null;
    if (uk == null || uk <= 0) {
      throw const FormatException('百度账户资料缺少合法 uk');
    }
    return BaiduAccountProfile(
      uk: uk,
      baiduName: _optionalString(json['baidu_name']),
      netdiskName: _optionalString(json['netdisk_name']),
      vipType: _optionalInt(json['vip_type']),
      avatarUrl: _optionalString(json['avatar_url']),
    );
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _optionalInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
