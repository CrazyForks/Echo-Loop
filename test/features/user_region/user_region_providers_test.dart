import 'dart:async';

import 'package:echo_loop/features/remote_config/remote_config.dart';
import 'package:echo_loop/features/subscription/services/purchase_service.dart';
import 'package:echo_loop/features/user_region/user_region.dart';
import 'package:echo_loop/features/user_region/user_region_providers.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePurchaseService extends StubPurchaseService {
  _FakePurchaseService(this._readStorefront);

  final Future<String?> Function() _readStorefront;
  int storefrontReads = 0;

  @override
  Future<String?> storefrontCountryCode() {
    storefrontReads += 1;
    return _readStorefront();
  }
}

RemoteConfig _config(String countryCode) => RemoteConfig(
  version: 1,
  ttlSeconds: 60,
  context: RemoteConfigContext(countryCode: countryCode),
  features: RemoteConfigFeatures.defaults,
);

void main() {
  group('UserRegionController', () {
    test('任一中国证据都会判定为中国用户', () async {
      final service = _FakePurchaseService(() async => 'CHN');
      final controller = UserRegionController(
        readPurchaseService: () => service,
        readDeviceCountryCode: () => 'US',
        isAppleStoreChannel: true,
        initialRemoteConfig: _config('US'),
      );
      addTearDown(controller.dispose);

      await controller.refresh(UserRegionRefreshTrigger.startup);

      expect(controller.state.isChinaUser, isTrue);
      expect(controller.state.matchedSources, [UserRegionEvidence.storefront]);
      expect(controller.state.storefront.countryCode, 'CHN');
    });

    test('系统地区为 CN 时不需要等待 Storefront 也立即命中', () {
      final controller = UserRegionController(
        readPurchaseService: () => _FakePurchaseService(() async => 'US'),
        readDeviceCountryCode: () => 'CN',
        isAppleStoreChannel: true,
        initialRemoteConfig: _config('US'),
      );
      addTearDown(controller.dispose);

      expect(controller.state.isChinaUser, isTrue);
      expect(controller.state.matchedSources, [
        UserRegionEvidence.deviceRegion,
      ]);
    });

    test('只设置中文语言但没有国家码不视为中国', () {
      final controller = UserRegionController(
        readPurchaseService: () => _FakePurchaseService(() async => null),
        readDeviceCountryCode: () => null,
        isAppleStoreChannel: true,
        initialRemoteConfig: _config('US'),
      );
      addTearDown(controller.dispose);

      expect(controller.state.isChinaUser, isFalse);
    });

    test('单项失败不阻断其他策略，全部未命中默认国际', () async {
      final controller = UserRegionController(
        readPurchaseService: () => _FakePurchaseService(
          () => throw StateError('storefront unavailable'),
        ),
        readDeviceCountryCode: () => throw StateError('locale unavailable'),
        isAppleStoreChannel: true,
        initialRemoteConfig: _config('US'),
      );
      addTearDown(controller.dispose);

      await controller.refresh(UserRegionRefreshTrigger.startup);

      expect(controller.state.isChinaUser, isFalse);
      expect(controller.state.storefront.status, UserRegionSourceStatus.failed);
      expect(
        controller.state.deviceRegion.status,
        UserRegionSourceStatus.failed,
      );
      expect(
        controller.state.clientConfig.status,
        UserRegionSourceStatus.available,
      );
    });

    test('非 Apple StoreKit 渠道跳过 Storefront', () async {
      final service = _FakePurchaseService(() async => 'CHN');
      final controller = UserRegionController(
        readPurchaseService: () => service,
        readDeviceCountryCode: () => 'US',
        isAppleStoreChannel: false,
        initialRemoteConfig: _config('US'),
      );
      addTearDown(controller.dispose);

      await controller.refresh(UserRegionRefreshTrigger.resume);

      expect(service.storefrontReads, 0);
      expect(
        controller.state.storefront.status,
        UserRegionSourceStatus.skipped,
      );
      expect(controller.state.isChinaUser, isFalse);
    });

    test('并发 refresh 复用同一次 Storefront 查询', () async {
      final completer = Completer<String?>();
      final service = _FakePurchaseService(() => completer.future);
      final controller = UserRegionController(
        readPurchaseService: () => service,
        readDeviceCountryCode: () => 'US',
        isAppleStoreChannel: true,
        initialRemoteConfig: _config('US'),
      );
      addTearDown(controller.dispose);

      final first = controller.refresh(UserRegionRefreshTrigger.startup);
      final second = controller.refresh(UserRegionRefreshTrigger.resume);
      completer.complete('US');
      await Future.wait([first, second]);

      expect(service.storefrontReads, 1);
    });

    test('Client Config 更新只重算缓存结论，不重复读取 Storefront', () async {
      final service = _FakePurchaseService(() async => 'US');
      final controller = UserRegionController(
        readPurchaseService: () => service,
        readDeviceCountryCode: () => 'US',
        isAppleStoreChannel: true,
        initialRemoteConfig: _config('US'),
      );
      addTearDown(controller.dispose);

      await controller.refresh(UserRegionRefreshTrigger.startup);
      controller.updateClientConfig(_config('CN'));

      expect(controller.state.isChinaUser, isTrue);
      expect(controller.state.matchedSources, [
        UserRegionEvidence.clientConfig,
      ]);
      expect(service.storefrontReads, 1);
    });
  });
}
