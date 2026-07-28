/// 媒体准备任务的终态。
///
/// UI 只根据该结果切换画面；播放器释放、学习状态写入等副作用仍由发起任务的
/// controller 负责，避免通用组件依赖具体业务 Provider。
enum MediaLoadResult {
  /// 媒体及其业务会话均已准备完成。
  ready,

  /// 当前 generation 加载失败，可由用户重试。
  failure,

  /// 当前 generation 已被切换媒体、退出页面或显式取消。
  cancelled,
}
