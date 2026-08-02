# Echo Loop 任务清单

> 最后更新：2026-08-02（Android 本地导入改为 content URI 按需读取）
> 当前焦点：Android 结束录音闪退（离线 ASR / Silero VAD）

## 最近完成

- [x] Android 本地音频导入改用原生 SAF 通道并按需读取：file_picker 的 Android 实现取名用 `getColumnIndexOrThrow(DISPLAY_NAME)` 且兜底写在同一个 try 里，遇到不返回该列的第三方 DocumentsProvider 会回传 null 撞上 non-null 的 `PlatformFile.name`，异常在插件内部抛出、调用方接不住（10.3.10 / 11.0.3 均未修）；且它选完就把每个 content URI 抄进 cache，只为造出一个 `path`。选择器为不误灰 m4a/flac 用的是 `type = "*/*"`，用户很容易连带选中大文件——实测选中 18 项要抄 722MB 的 apk，真正的音频只有 3.5MB，被接受的音频还会被抄两遍（cache + `tmp/audio_import`）。

  改为自家通道，`ACTION_OPEN_DOCUMENT` 多选、不申请广泛存储权限，**选择阶段零落盘**：只回 `{uri, name, size}`，URI 放进 `PlatformFile.identifier`、`path` 恒为 null；字幕配对时走 `readBytes`（按实际字节数卡 16MiB 上限，不信 provider 报的 size——会漏报 DISPLAY_NAME 的 provider 同样可能不报 size），音频在点导入时走 `copyToFile` 从 URI 一次性流进暂存区、写失败即删半成品，复制次数与桌面端一致。

  取名按 null projection 查整行（部分 provider 点名要 DISPLAY_NAME 反而给不出来，要整行却是全的），从 `_display_name` → `_data` → 文档 ID → URI 末段收集候选并**优先取带扩展名的**（文档 ID 常形如 `primary:Download/talk.mp3`）——只退到 URI 末段拿到的多是 `msf:1234`，没后缀，正常音频会被白名单当成「不支持的格式」静默拒掉。不看 MIME、不看文件头、不改写已有扩展名，是否受支持仍由 `classifyImportFiles` 判定。挑名逻辑抽成纯 Kotlin 的 `PickedFileNaming`，JVM 单测 11 条覆盖各种畸形回传。`Activity Result` 走 `startActivityForResult` + `MainActivity.onActivityResult` 转发，`MainActivity` 保持 `AudioServiceActivity` 基类不变；iOS 与桌面端仍走 file_picker。（2026-08-02）
- [x] 修复本地导入面板「空态死界面」：embedded 面板内没有独立的「选择音频文件」按钮（那个只在独立弹窗里渲染），此前 `_pickedFiles` 为空时底部主按钮是禁用的「导入」，用户没有任何重新唤起选择器的入口——只选中字幕（字幕不能单独导入）或把已选文件全部删掉都会落到这个状态，只能点左上返回箭头退回来源页重进。现在空态主按钮改为可点的「选择音频文件」。同时补上第二个缺陷：只选中字幕时既不进「不支持格式」提示分支也不进列表 setState 分支，面板完全静默，现按 `_AudioErrorKind.noAudioSelected` 给出「未选择音频文件」内联提示（有不支持格式时不叠加，`_error` 是单值）。已选列表非空时再选一次只有字幕仍不清空列表。回归测试覆盖「只选字幕后提示 + 可再次唤起选择器」与「删空列表后可重新选择」（2026-08-02）
- [x] 复述 AI 评估结果弹窗成型（对齐服务端评估结果结构 + 重做展示）：模型改为 `summary` / `keyPoints[]` / `corrections[]` / `suggestion` / `rating`，`rating` 与 `keyPoints[].status` 可空以免流式过程中先渲染出会被推翻的判定；要点条目携带母语要点陈述、原文摘录、转录摘录与反馈四段，状态覆盖「覆盖 / 部分 / 遗漏 / 偏差 / 多说」，纠错分为 grammar / wordChoice / redundancy / phrasing / cohesion 五类（冗余 / 说法 / 衔接不加删除线，原句本身不算错）。弹窗重做为「评级 Hero + 转录折叠卡 + 要点卡列表 + 纠错对照卡 + 建议 callout」，首帧改为独立的 transcript 帧，转录到达时弹窗即开、内容随后逐段流入；失败态按 errorCode 给文案并支持重试。视觉上判定色只出现在要点卡首行胶囊与状态图标，附属行退成中性文字，卡面统一收敛为 `retell_review_rating_style.dart` 里的 `retellCardDecoration()`（近白卡底 + 提亮细描边，替掉三处各自抄的 `surfaceContainerHighest` 大灰块）。`retell_review_report.dart` 按职责拆成 `retell_review_key_points.dart` / `retell_review_corrections.dart` / `retell_review_transcript_card.dart`；录音试听状态从 `AudioPlaybackService` 收敛到新的 `AudioPreviewController`（服务只负责播，UI 状态基于 `play()` 的 Future 维护，按钮滑出视口被回收后重建仍能读到真实状态）；新增 `lib/models/retell_review_sample.dart` 调试假数据，把 `retellReviewSampleEnabled` 改成 true 热重启即可离线调界面（2026-08-01）
- [x] iOS 本地导入支持选择 LRC 字幕：补齐 `.lrc` 的 UTI 与文档类型声明，避免系统“文件”选择器将 LRC 置灰；iOS 配置测试覆盖 SRT / VTT / LRC 三种字幕格式（2026-07-31）
- [x] 复述页接入流式 AI 评估：录音 badge 同生命周期入口、16kHz 单声道临时转码与 2MB 前端限制、NDJSON 渐显结果弹窗；入口调整为对称的「图标 + AI 评估」badge，结果改为分层学习反馈报告；点击即用户接管，弹窗可播放录音（2026-07-30）
- [x] 统一练习页倒计时点击为“用户接管流程”，保留停止脚标并移除快进入口：录音页完成后保持当前句/段手动接管，非录音页停在当前内容（2026-07-30）
- [x] 修复 Chatbot widget 测试缺失 analytics provider 覆盖导致的 CI 失败（2026-07-28）
- [x] 版本号升级至 1.0.28（2026-07-28）

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
