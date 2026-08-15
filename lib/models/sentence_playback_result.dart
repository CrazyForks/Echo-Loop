/// 句子或区间播放的终态。
enum SentencePlaybackResult {
  /// 当前 session 已实际播放到请求的句尾。
  completed,

  /// 当前播放被用户操作或新的 session 抢占。
  cancelled,

  /// 播放器提前结束、请求无效或底层播放失败。
  failed,
}
