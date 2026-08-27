import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_logger.dart';
import '../../../services/refresh_coordinator.dart';
import '../../../utils/app_data_dir.dart';

sealed class PaddlePlansRefreshOutcome {
  const PaddlePlansRefreshOutcome();
}

class PaddlePlansThrottled extends PaddlePlansRefreshOutcome {
  const PaddlePlansThrottled();
}

class PaddlePlansUnchanged extends PaddlePlansRefreshOutcome {
  const PaddlePlansUnchanged();
}

class PaddlePlansUpdated extends PaddlePlansRefreshOutcome {
  const PaddlePlansUpdated();
}

class PaddlePlansFailed extends PaddlePlansRefreshOutcome {
  const PaddlePlansFailed(this.error);
  final Object error;
}

/// Paddle plans 的独立缓存与刷新服务；缓存数据不与 catalog 共享。
///
/// 文件位于 `<Application Support>/cache/paddle_plans/`：
/// `plans.json` 保存完整 API 响应，`plans.meta.json` 保存 hash、请求时间和服务端时间。
class PaddlePlansService {
  PaddlePlansService({
    required Dio dio,
    Future<Directory> Function()? resolveDir,
    bool persist = true,
  }) : _dio = dio,
       _resolveDir = resolveDir ?? _defaultDir,
       _persist = persist;

  final Dio _dio;
  final Future<Directory> Function() _resolveDir;
  final bool _persist;
  final RefreshCoordinator<String, PaddlePlansRefreshOutcome> _refresh =
      RefreshCoordinator<String, PaddlePlansRefreshOutcome>();
  Map<String, dynamic>? _cached;
  DateTime? _lastFetchedAt;
  String? _hash;
  Map<String, dynamic>? get cached => _cached;
  bool get hasInitialized => _initialized;
  bool _initialized = false;

  static Future<Directory> _defaultDir() async {
    final root = await resolveAppCacheDirectory();
    return Directory(p.join(root.path, 'paddle_plans'));
  }

  Future<File> _file(String name) async =>
      File(p.join((await _resolveDir()).path, name));

  Future<Map<String, dynamic>?> loadCachedPlans() async {
    if (!_persist) return null;
    try {
      final payload = await _file('plans.json');
      final meta = await _file('plans.meta.json');
      if (!await payload.exists() || !await meta.exists()) return null;
      final data = jsonDecode(await payload.readAsString());
      final metadata = jsonDecode(await meta.readAsString());
      if (data is! Map<String, dynamic> || metadata is! Map<String, dynamic>) {
        throw const FormatException('invalid Paddle cache');
      }
      _cached = data;
      _hash = metadata['contentHash'] as String?;
      _lastFetchedAt = DateTime.tryParse(
        metadata['lastFetchedAt'] as String? ?? '',
      );
      _initialized = true;
      AppLogger.log(
        'Subscription',
        'Paddle plans 缓存加载成功: fetchedAt=$_lastFetchedAt',
      );
      return data;
    } catch (error) {
      AppLogger.log('Subscription', 'Paddle plans 本地缓存读取失败: $error');
      _initialized = true;
      return null;
    }
  }

  Future<PaddlePlansRefreshOutcome> refresh({bool force = false}) => _refresh
      .run(
        key: 'paddle-plans',
        force: force,
        lastRefreshedAt: _lastFetchedAt,
        throttleWindow: const Duration(days: 1),
        refresh: _doRefresh,
      )
      .then(
        (run) => switch (run) {
          RefreshThrottled<PaddlePlansRefreshOutcome>() =>
            const PaddlePlansThrottled(),
          RefreshCompleted<PaddlePlansRefreshOutcome>(:final result) => result,
        },
      );

  Future<PaddlePlansRefreshOutcome> _doRefresh() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/paddle/plans',
      );
      final data = response.data;
      if (data == null || data['plans'] is! List) {
        throw const FormatException('invalid Paddle response');
      }
      final body = jsonEncode(data);
      final hash = sha256.convert(utf8.encode(body)).toString();
      final now = DateTime.now();
      if (hash == _hash) {
        if (_persist) {
          try {
            await _writeMeta(
              hash,
              now,
              data['serverTime'] as String? ?? now.toIso8601String(),
            );
          } catch (error) {
            // 与 catalog 一致：内容未变化时，meta 写失败不应否定已成功的请求。
            AppLogger.log(
              'Subscription',
              'Paddle plans meta 写入失败（忽略）: $error',
            );
          }
        }
        _lastFetchedAt = now;
        AppLogger.log('Subscription', 'Paddle plans unchanged: fetchedAt=$now');
        return const PaddlePlansUnchanged();
      }
      if (_persist) {
        final dir = await _resolveDir();
        await dir.create(recursive: true);
        await (await _file('plans.json')).writeAsString(body);
        await _writeMeta(
          hash,
          now,
          data['serverTime'] as String? ?? now.toIso8601String(),
        );
      }
      _cached = data;
      _hash = hash;
      _lastFetchedAt = now;
      _initialized = true;
      AppLogger.log('Subscription', 'Paddle plans updated: fetchedAt=$now');
      return const PaddlePlansUpdated();
    } catch (error) {
      AppLogger.log('Subscription', 'Paddle plans 刷新失败: $error');
      return PaddlePlansFailed(error);
    }
  }

  Future<void> _writeMeta(
    String hash,
    DateTime fetchedAt,
    String serverTime,
  ) async => (await _file('plans.meta.json')).writeAsString(
    jsonEncode({
      'contentHash': hash,
      'lastFetchedAt': fetchedAt.toIso8601String(),
      'serverTime': serverTime,
    }),
  );
}
