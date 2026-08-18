import 'package:echo_loop/features/baidu_netdisk/models/baidu_account_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析账号名、网盘昵称和 UK', () {
    final profile = BaiduAccountProfile.fromBaiduJson({
      'uk': '4165472688',
      'baidu_name': ' account-name ',
      'netdisk_name': ' 网盘昵称 ',
      'vip_type': '2',
      'avatar_url': ' https://example.com/avatar.jpg ',
    });

    expect(profile.uk, 4165472688);
    expect(profile.baiduName, 'account-name');
    expect(profile.netdiskName, '网盘昵称');
    expect(profile.vipType, 2);
    expect(profile.membershipLabel, 'svip');
    expect(profile.avatarUrl, 'https://example.com/avatar.jpg');
  });

  test('昵称缺失时保留 UK', () {
    final profile = BaiduAccountProfile.fromBaiduJson({'uk': 7});

    expect(profile.uk, 7);
    expect(profile.baiduName, isNull);
    expect(profile.netdiskName, isNull);
    expect(profile.vipType, isNull);
    expect(profile.membershipLabel, 'unknown');
    expect(profile.avatarUrl, isNull);
  });

  test('解析普通用户会员类型', () {
    final profile = BaiduAccountProfile.fromBaiduJson({'uk': 7, 'vip_type': 0});

    expect(profile.membershipLabel, 'free');
  });

  test('缺少合法 UK 时拒绝响应', () {
    expect(
      () => BaiduAccountProfile.fromBaiduJson({'baidu_name': 'name'}),
      throwsFormatException,
    );
  });
}
