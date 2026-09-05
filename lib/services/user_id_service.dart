/// 匿名用户 ID 服务
///
/// 使用 [FlutterSecureStorage]（Keychain / Credential Manager）持久化用户 ID，
/// 在 iOS / macOS / Windows 上卸载重装后可恢复。
/// Android 上卸载后 ID 会丢失（平台限制），重装后生成新 ID。
///
/// 首次使用时会从 SharedPreferences 迁移旧 ID，保证已有用户不换 ID。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _anonymousIdKey = 'anonymous_id';

/// 匿名 ID 的单次初始化 Future。
///
/// main 在 `runApp()` 前启动它但不等待；需要 ID 的业务必须 await provider，避免
/// 首帧路径读取尚未写入的 `late String`。
late Future<String> _userIdReady;

/// 初始化用户 ID 服务，返回用户 ID
///
/// 读取优先级：SecureStorage → SharedPreferences（迁移） → 新建 UUID v4。
/// [secureStorage] 参数仅用于测试注入。
Future<String> initUserIdService(
  SharedPreferences prefs, {
  FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
}) async {
  final storage = secureStorage;

  // 1. 优先从 SecureStorage 读取
  var id = await storage.read(key: _anonymousIdKey);

  if (id == null) {
    // 2. 从 SharedPreferences 迁移旧值，或生成新 UUID v4
    id = prefs.getString(_anonymousIdKey) ?? const Uuid().v4();

    // 写入 SecureStorage 持久化
    await storage.write(key: _anonymousIdKey, value: id);
  }

  // 迁移完成后删除 SharedPreferences 中的旧值
  if (prefs.containsKey(_anonymousIdKey)) {
    await prefs.remove(_anonymousIdKey);
  }

  return id;
}

/// 启动本进程的匿名 ID 初始化，并暴露同一个 Future 给所有消费者。
Future<String> startUserIdService(SharedPreferences prefs) {
  _userIdReady = initUserIdService(prefs);
  return _userIdReady;
}

/// 清除用户 ID（隐私合规：用户撤销同意时调用）
Future<void> clearUserId() async {
  const storage = FlutterSecureStorage();
  await storage.delete(key: _anonymousIdKey);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_anonymousIdKey);
}

/// 用户 ID Provider。消费者必须 await 返回的 Future。
final userIdProvider = Provider<Future<String>>((ref) {
  return _userIdReady;
});
