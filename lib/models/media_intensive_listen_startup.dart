import 'media_load_result.dart';

/// 视频逐句精听路由携带的一次性启动命令。
///
/// 路由只传递类型安全的命令，不携带 Provider 或 BuildContext；目标页面因此可以
/// 自主管理加载、失败重试和退出取消。
class MediaIntensiveListenStartup {
  const MediaIntensiveListenStartup({
    required this.loadKey,
    required this.load,
    required this.cancel,
  });

  final Object loadKey;
  final Future<MediaLoadResult> Function() load;
  final Future<void> Function() cancel;
}
