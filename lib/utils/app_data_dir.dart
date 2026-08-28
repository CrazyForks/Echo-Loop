import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// 应用用户数据的根目录。
///
/// 返回 `Application Support` 目录，该目录不会在 iOS「设置 > 存储」中暴露，
/// 但仍会被 iCloud 备份。替代之前散布在各处的 `getApplicationDocumentsDirectory()` 调用。
///
/// 结果在首次调用后缓存，避免重复的平台通道调用。
Future<Directory> getAppDataDirectory() async {
  if (_override != null) return _override!;
  return _cached ??= await _resolve();
}

/// 应用级缓存根目录；各 feature 必须在此目录下使用独立命名空间。
Future<Directory> resolveAppCacheDirectory() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/cache');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// 仅用于测试：覆盖 [getAppDataDirectory] 的返回值。
///
/// 设为 `null` 恢复默认行为。
@visibleForTesting
set appDataDirectoryOverride(Directory? dir) {
  _override = dir;
  _cached = null;
}

Directory? _cached;
Directory? _override;

Future<Directory> _resolve() async {
  final dir = await getApplicationSupportDirectory();
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 持久化日志目录（落盘日志，跨进程保留，供日志页查看和导出）。
///
/// 目录仅由日志输出管理，避免轮转清理误触应用数据目录内的其他诊断文件。
Future<String> appLogDirectoryPath() async {
  final dir = await getAppDataDirectory();
  return '${dir.path}/logs';
}

/// ASR 推理诊断文件目录。
Future<String> asrInferenceLogDirectoryPath() async {
  final dir = Directory('${(await getAppDataDirectory()).path}/logs');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir.path;
}
