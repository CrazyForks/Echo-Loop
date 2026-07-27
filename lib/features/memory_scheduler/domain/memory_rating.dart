/// 记忆调度向上层暴露的四级复习反馈。
library;

/// 用户对本次回忆质量的评价。
enum MemoryRating {
  /// 未能回忆，需要尽快再次练习。
  again,

  /// 回忆困难。
  hard,

  /// 正常回忆。
  good,

  /// 轻松回忆。
  easy,
}
