// ignore_for_file: implementation_imports

import 'dart:ffi';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';
import 'package:media_kit/src/player/native/utils/android_helper.dart';
import 'package:media_kit/src/player/native/utils/native_reference_holder.dart';

/// 初始化 media_kit，并在 debug hot restart 前置清理旧 mpv callback。
///
/// media_kit 1.2.6 的 debug 旧引用清理只对旧 mpv handle 发送 `quit`。
/// 热重启后旧 isolate 的 FFI wakeup callback 已被删除，旧 mpv 线程在处理
/// `quit` 过程中仍可能触发该 callback，导致 Dart VM 报
/// “Callback invoked after it has been deleted”。这里先把旧 handle 的
/// wakeup callback 清空，再交给 mpv 退出，避免调用已失效的 Dart callback。
void ensureMediaKitInitialized({String? libmpv}) {
  if (kIsWeb || !kDebugMode) {
    MediaKit.ensureInitialized(libmpv: libmpv);
    return;
  }

  AndroidHelper.ensureInitialized();
  NativeLibrary.ensureInitialized(libmpv: libmpv);
  NativeReferenceHolder.ensureInitialized((references) {
    final addresses = references
        .map((reference) => reference.address)
        .where((address) => address != 0)
        .toList(growable: false);
    if (addresses.isEmpty) return;

    const tag = NativeReferenceHolder.kTag;
    print('$tag Found ${addresses.length} reference(s).');
    print('$tag Disposing:\n${addresses.join('\n')}');

    final mpv = generated.MPV(DynamicLibrary.open(NativeLibrary.path));
    MediaKitHotRestartReferenceCleaner(
      clearWakeupCallback: (address) {
        final handle = Pointer<generated.mpv_handle>.fromAddress(address);
        mpv.mpv_set_wakeup_callback(handle, nullptr, nullptr);
      },
      quit: (address) {
        final handle = Pointer<generated.mpv_handle>.fromAddress(address);
        final cmd = 'quit'.toNativeUtf8();
        try {
          mpv.mpv_command_string(handle, cmd.cast());
        } finally {
          calloc.free(cmd);
        }
      },
    ).clean(addresses);
  });

  MediaKit.ensureInitialized(libmpv: libmpv);
}

/// 对旧 mpv handle 执行可测试的热重启清理顺序。
class MediaKitHotRestartReferenceCleaner {
  const MediaKitHotRestartReferenceCleaner({
    required this.clearWakeupCallback,
    required this.quit,
  });

  final void Function(int address) clearWakeupCallback;
  final void Function(int address) quit;

  /// 先断开 native -> Dart callback，再发送退出命令。
  void clean(List<int> addresses) {
    for (final address in addresses) {
      clearWakeupCallback(address);
    }
    for (final address in addresses) {
      quit(address);
    }
  }
}
