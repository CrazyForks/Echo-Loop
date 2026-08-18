/// 百度 credential 的 secure storage 持久化。
///
/// 只使用一个 JSON key 保存完整 bundle；任何读写异常都向上暴露为明确的存储错误，
/// 不回退到 SharedPreferences 或明文文件。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/baidu_credential_bundle.dart';

const _baiduCredentialStorageKey = 'baidu_netdisk_credential_v1';
const _baiduForceLoginOnceStorageKey = 'baidu_force_login_once';

/// Credential 存储错误类型。
enum BaiduCredentialStoreErrorKind {
  /// 当前平台 secure storage 不可用。
  unavailable,

  /// 读取失败。
  readFailed,

  /// 写入失败。
  writeFailed,

  /// 删除失败。
  deleteFailed,

  /// 已保存 JSON 损坏。
  parseFailed,
}

/// Credential 存储异常。
class BaiduCredentialStoreException implements Exception {
  /// 构造存储异常。
  const BaiduCredentialStoreException({
    required this.kind,
    required this.message,
    this.cause,
  });

  /// 错误类型。
  final BaiduCredentialStoreErrorKind kind;

  /// 可展示或记录的非敏感信息。
  final String message;

  /// 原始异常对象。
  final Object? cause;

  @override
  String toString() => 'BaiduCredentialStoreException($kind, $message)';
}

/// 百度 credential 存储抽象。
abstract interface class BaiduCredentialStore {
  /// 读取 credential；无缓存返回 null。
  Future<BaiduCredentialBundle?> read();

  /// 写入完整 credential bundle。
  Future<void> write(BaiduCredentialBundle credential);

  /// 清除 credential。
  Future<void> clear();

  /// 读取退出后待消费的一次性强制登录标志。
  Future<bool> readForceLoginOnce();

  /// 写入退出后待消费的一次性强制登录标志。
  Future<void> writeForceLoginOnce();

  /// 清除已经消费的一次性强制登录标志。
  Future<void> clearForceLoginOnce();
}

/// 基于 flutter_secure_storage 的实现。
class SecureBaiduCredentialStore implements BaiduCredentialStore {
  /// 构造 secure storage 实现。
  SecureBaiduCredentialStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    TargetPlatform? platform,
  }) : _storage = storage,
       _platform = platform;

  final FlutterSecureStorage _storage;
  final TargetPlatform? _platform;

  TargetPlatform get _effectivePlatform => _platform ?? defaultTargetPlatform;

  @override
  Future<BaiduCredentialBundle?> read() async {
    final raw = await _guardStorage(
      () => _storage.read(key: _baiduCredentialStorageKey),
      fallbackKind: BaiduCredentialStoreErrorKind.readFailed,
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      return BaiduCredentialBundle.fromJson(jsonDecode(raw));
    } catch (error) {
      throw BaiduCredentialStoreException(
        kind: BaiduCredentialStoreErrorKind.parseFailed,
        message: '百度网盘凭证缓存已损坏，请重新授权。',
        cause: error,
      );
    }
  }

  @override
  Future<void> write(BaiduCredentialBundle credential) async {
    await _guardStorage(
      () => _storage.write(
        key: _baiduCredentialStorageKey,
        value: jsonEncode(credential.toJson()),
      ),
      fallbackKind: BaiduCredentialStoreErrorKind.writeFailed,
    );
  }

  @override
  Future<void> clear() async {
    await _guardStorage(
      () => _storage.delete(key: _baiduCredentialStorageKey),
      fallbackKind: BaiduCredentialStoreErrorKind.deleteFailed,
    );
  }

  @override
  Future<bool> readForceLoginOnce() async {
    final raw = await _guardStorage(
      () => _storage.read(key: _baiduForceLoginOnceStorageKey),
      fallbackKind: BaiduCredentialStoreErrorKind.readFailed,
    );
    return raw == 'true';
  }

  @override
  Future<void> writeForceLoginOnce() {
    return _guardStorage(
      () => _storage.write(key: _baiduForceLoginOnceStorageKey, value: 'true'),
      fallbackKind: BaiduCredentialStoreErrorKind.writeFailed,
    );
  }

  @override
  Future<void> clearForceLoginOnce() {
    return _guardStorage(
      () => _storage.delete(key: _baiduForceLoginOnceStorageKey),
      fallbackKind: BaiduCredentialStoreErrorKind.deleteFailed,
    );
  }

  Future<T> _guardStorage<T>(
    Future<T> Function() action, {
    required BaiduCredentialStoreErrorKind fallbackKind,
  }) async {
    try {
      return await action();
    } on MissingPluginException catch (error) {
      throw _unavailable(error);
    } on PlatformException catch (error) {
      if (_effectivePlatform == TargetPlatform.linux) {
        throw _unavailable(error);
      }
      throw BaiduCredentialStoreException(
        kind: fallbackKind,
        message: '百度网盘凭证安全存储失败。',
        cause: error,
      );
    } catch (error) {
      throw BaiduCredentialStoreException(
        kind: fallbackKind,
        message: '百度网盘凭证安全存储失败。',
        cause: error,
      );
    }
  }

  BaiduCredentialStoreException _unavailable(Object error) {
    return BaiduCredentialStoreException(
      kind: BaiduCredentialStoreErrorKind.unavailable,
      message: '当前系统缺少可用的安全密钥环，无法保存百度网盘授权。',
      cause: error,
    );
  }
}
