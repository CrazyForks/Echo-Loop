/// 意群时间区间播放的最小契约。
///
/// 讲解 UI 只表达用户要播放或取消某材料中的一个意群，不依赖具体媒体引擎；不同学习
/// 会话可各自注入实现，避免跨材料复用全局播放器。
abstract interface class SenseGroupRangePlayback {
  /// 播放 [audioItemId] 的 [start] 至 [end]；新的调用会使旧播放失效。
  Future<void> play(String audioItemId, Duration start, Duration end);

  /// 取消当前意群播放，并使迟到的异步回调失效。
  Future<void> cancel();
}
