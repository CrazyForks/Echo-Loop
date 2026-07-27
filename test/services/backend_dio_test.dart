/// 后端 Dio 工厂 [createBackendDio] 测试。
///
/// 覆盖：工厂产出的 Dio 已在 BaseOptions 注入 client-info 公共 header（平台/渠道/版本），
/// 与 [clientInfoHeaders] 一致；appVersion 缺省时省略版本 header；baseUrl / 超时按参数设置。
library;

import 'package:echo_loop/services/backend_dio.dart';
import 'package:echo_loop/services/api_log_interceptor.dart';
import 'package:echo_loop/services/client_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('createBackendDio', () {
    test('BaseOptions.headers 与 clientInfoHeaders 一致（携带平台/渠道/版本）', () {
      final dio = createBackendDio(
        baseUrl: 'https://example.com',
        appVersion: '1.2.3',
      );
      expect(dio.options.headers, clientInfoHeaders(appVersion: '1.2.3'));
      // 平台标识随请求上送（测试宿主平台合法则携带）。
      final platform = clientPlatformName();
      if (platform.isEmpty) {
        expect(dio.options.headers.containsKey(kAppPlatformHeader), isFalse);
      } else {
        expect(dio.options.headers[kAppPlatformHeader], platform);
      }
      expect(dio.options.headers[kAppVersionHeader], '1.2.3');
      dio.close();
    });

    test('appVersion 缺省时省略版本 header', () {
      final dio = createBackendDio(baseUrl: 'https://example.com');
      expect(dio.options.headers.containsKey(kAppVersionHeader), isFalse);
      dio.close();
    });

    test('baseUrl 与超时按参数设置', () {
      final dio = createBackendDio(
        baseUrl: 'https://api.example.com',
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 7),
      );
      expect(dio.options.baseUrl, 'https://api.example.com');
      expect(dio.options.connectTimeout, const Duration(seconds: 3));
      expect(dio.options.receiveTimeout, const Duration(seconds: 7));
      dio.close();
    });

    test('默认超时为连接 15 秒、接收 30 秒', () {
      final dio = createBackendDio(baseUrl: 'https://api.example.com');

      expect(dio.options.connectTimeout, const Duration(seconds: 15));
      expect(dio.options.receiveTimeout, const Duration(seconds: 30));
      dio.close();
    });

    test('默认安装一个后端 API 日志拦截器并支持自定义 tag', () {
      final logs = <String>[];
      final dio = createBackendDio(
        baseUrl: 'https://api.example.com',
        apiLogTag: 'CATALOG',
        apiLogPrint: logs.add,
      );

      final interceptors = dio.interceptors.whereType<ApiLogInterceptor>();
      expect(interceptors, hasLength(1));
      expect(interceptors.single.tag, 'CATALOG');
      dio.close();
    });
  });
}
