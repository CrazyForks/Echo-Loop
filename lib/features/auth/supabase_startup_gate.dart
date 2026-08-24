import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/auth_config.dart' as auth_config;

/// Supabase SDK 的进程级就绪信号。
///
/// 认证 SDK 在首帧后才初始化；所有可能间接访问 `Supabase.instance` 的
/// provider 都必须先读取此 gate，避免热重启期间触发 SDK 的断言。
class SupabaseStartupGate {
  SupabaseStartupGate._();

  static final ValueNotifier<bool> _isReady = ValueNotifier<bool>(
    !auth_config.isAuthConfigured,
  );

  static bool get isReady => _isReady.value;

  /// 标记 SDK 已成功初始化；重复调用保持幂等。
  static void markReady() {
    _isReady.value = true;
  }

  static void addListener(VoidCallback listener) {
    _isReady.addListener(listener);
  }

  static void removeListener(VoidCallback listener) {
    _isReady.removeListener(listener);
  }
}

/// 提供给认证、订阅与更新依赖图的响应式 Supabase 可用状态。
final supabaseSdkReadyProvider = Provider<bool>((ref) {
  void onChanged() => ref.invalidateSelf();
  SupabaseStartupGate.addListener(onChanged);
  ref.onDispose(() => SupabaseStartupGate.removeListener(onChanged));
  return SupabaseStartupGate.isReady;
});
