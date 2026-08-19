import 'package:dio/dio.dart';

/// 可由统一下载协调器管理的资源。
///
/// 资源自身负责安装和完整性校验；协调器只负责任务生命周期、并发和状态。
abstract interface class DownloadResource {
  String get id;
  String get displayName;

  Future<bool> isReady();

  Future<void> download({
    required void Function(int receivedBytes, int? totalBytes) onProgress,
    required CancelToken cancelToken,
  });

  Future<void> deletePartial();
}
