# Echo Loop 任务清单

> 最后更新：2026-07-28（清理已完成历史；完整快照已归档）
> 当前焦点：Android 结束录音闪退（离线 ASR / Silero VAD）

## 当前优先级

### P0

- [ ] Android 离线 ASR：结束录音后仍闪退。当前已确认崩在 sherpa-onnx 的 Silero VAD native 推理，现有 cpu provider、AudioRecord 串行、自适应跳过 VAD 都未解决；下一步必须拿到真机 `logcat` 与 `/data/tombstones` 再定方案。

### P1

- [ ] 启动埋点附带 4 类授权状态：手动验证 PostHog Live Events / Persons / Insights。
- [ ] 段落复述页面复用统一录音识别模块。
- [ ] 百度网盘跨平台音频导入：后端 OAuth 会话（后端仓库实现；当前 Flutter 仓库不伪造生产后端）。
- [ ] 百度网盘跨平台音频导入：跨平台验证与发布准备。

### P2

- [ ] 难句跟读、难句补练复制逐句精听的左滑/右滑切句机制：使用 `PageView` 单向同步，左滑下一句、右滑上一句，并复用统一的切句状态入口与交互语义。
- [ ] 计算每个学习任务的预计/实际耗时，并展示在学习页入口。
- [ ] 学习 Tab 点击学习/复习后直接进入学习页面，跳过学习计划页。
- [ ] 学习 Tab 展示“今日完成任务”折叠区。
- [ ] 支持自定义背景、背景音。
- [ ] 播放完成音效、任务完成动画与音效。
- [ ] 埋点能力按中国大陆 / 全球环境拆分落地。

## 约束与范围

### 启动埋点附带 4 类授权状态

- [ ] 不新增教育弹窗。
- [ ] 不调整现有系统权限弹窗时机。
- [ ] 不补 AppLifecycle 恢复监听。
- [ ] 不做 Android 13+ 通知权限专门 UI 验证。

## 历史归档

- [2026-07-28 清理前完整任务快照](./docs/tasks-archive/tasks-2026-07-28-full.md)
- [2026-07-12 全量任务快照](./docs/tasks-archive/tasks-2026-07-12-full.md)
- [Milestone 2 - 学习流程引擎](./docs/tasks-archive/milestone-2-learning-engine.md)
- [Milestone 3 - 收藏与标注体系 + 体验优化](./docs/tasks-archive/milestone-3-completed.md)
- [Milestone 4 - 功能完善与体验打磨](./docs/tasks-archive/milestone-4-features-and-polish.md)
- [Milestone 5 - 登录认证 / Podcast / 离线 ASR / 字幕编辑器](./docs/tasks-archive/milestone-5-completed.md)

## 维护规则

- 新任务写入“当前优先级”，按 P0 / P1 / P2 排序。
- 完成后仅在主文件保留必要结论；详细实施记录归档到 `docs/tasks-archive/`。
- 里程碑状态变化时同步更新 `PLAN.md`。
