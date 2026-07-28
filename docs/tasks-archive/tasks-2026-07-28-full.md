# Echo Loop 任务清单

> 最后更新：2026-07-27（导入编辑优化后的中英文全量文案）
> 当前焦点：Android 结束录音闪退（离线 ASR / Silero VAD）——仍未解决

## 当前优先级

### P0

- [ ] Android 离线 ASR：结束录音后仍闪退。当前已确认崩在 sherpa-onnx 的 Silero VAD native 推理，现有 cpu provider、AudioRecord 串行、自适应跳过 VAD 都未解决；下一步必须拿到真机 `logcat` 与 `/data/tombstones` 再定方案。

## 通用 Chatbot 组件

> 实现规格见 [docs/chatbot-implementation-plan.md](./docs/chatbot-implementation-plan.md)。多轮对话式 AI 助手，一套可插拔组件（sheet + 全屏页双载体），首接入点为句子讲解页。发布由编译期常量 `kChatbotEnabled`（默认 false）控制，后端就绪前不对用户暴露。不抢占当前录音识别焦点任务。

### P0

- [x] T0 流程登记（本条）。**完成时间**: 2026-07-18
- [x] T1 数据模型与配置（chat_role/chat_message/chatbot_config/chat_session_state/chatbot_flags）。**完成时间**: 2026-07-18
- [x] T2 流式协议层（ndjson_text_stream）。**完成时间**: 2026-07-18
- [x] T3 ChatApiClient + FakeChatApiClient + provider。**完成时间**: 2026-07-18
- [x] T4 额度门枚举（PremiumFeature.aiChat）。**完成时间**: 2026-07-18
- [x] T5 ChatSessionController（防竞态状态机）。**完成时间**: 2026-07-18
- [x] T6 UI 组件 + markdown（gpt_markdown）。**完成时间**: 2026-07-18
- [x] T7 双语文案（en/zh）。**完成时间**: 2026-07-18
- [x] T8 两载体 + 首接入点 + 发布开关。**完成时间**: 2026-07-18

### P1

- [x] T9 边界打磨 + e2e（竞态回归 widget 测试；发送→流式→完成 / 发送→停止 均以 ChatView widget 测试覆盖）。本机 `integration_test -d macos` 环境已知异常（见 MEMORY），未跑全量 e2e binding。**完成时间**: 2026-07-18
- [x] T10 清空 / 重新生成（载体 header 溢出菜单 clear/retry）。**完成时间**: 2026-07-18
- [x] T11 气泡操作栏：user 复制+修改、assistant 复制+重新生成；修改走输入框回填（不分叉）；图标用复刻 ChatGPT 的 SVG（flutter_svg），随主题着色。**完成时间**: 2026-07-18
- [x] T12 AI 回答选择文本 + 选区气泡操作条：官方 `SelectionArea` + `contextMenuBuilder` 标准方案（稳定、贴官方惯用法）。
  - 决策：此前自定义实现（`AppleTextSelectionControls` + `ImmediateMultiDrag` 自驱端点 + 放大镜 + 桌面分支）bug 反复，已整体删除，回到干净基线，改走官方标准方案。
  - 已完成（清理）：删除全部旧自定义选择文本代码与测试（3 widget + 3 test）。**完成时间**: 2026-07-20
  - 已完成（步骤 1 · 选择）：AI 回答用 `SelectionArea` 可选中任意连续文本（跨 markdown 块、含行内代码 `` `code` ``）；`_InlineCodeMd` 半透明底色让选中高亮透出。**完成时间**: 2026-07-20
  - 已完成（步骤 2 · 操作条）：`SelectableAssistantMarkdown` 用 `contextMenuBuilder` 在选区上方弹出「复制 / 问 AI」气泡；抽出可复用组件 `SelectionToolbar`（横向 `CupertinoTextSelectionToolbar` 胶囊，三端一致，非 macOS 纵向下拉）；`SelectionToolbar.anchorsForSelection` 始终按选区几何算锚点（修右键弹在鼠标处），并保留 Flutter 默认文字间距；问 AI 接回 `onFollowUp` 链路。**完成时间**: 2026-07-20
  - 已确认（平台默认行为）：移动端按 Flutter 原生长按/拖拽结束弹出；桌面端回到 Flutter 默认交互，仅右键/上下文菜单触发同一套 `SelectionToolbar`，不做选区完成自动弹出；同时打开 `kChatbotUseFakeApi` 方便本地假流数据验收。**确认时间**: 2026-07-20
  - 已完成（步骤 4 · 气泡按钮等宽）：`SelectionToolbar` 按最长本地化文案统一按钮宽度，修复中文「复制 / 问 AI」分割线不居中的问题，并补中文等宽 widget 回归。**完成时间**: 2026-07-20
- [x] T13 学习任务页接入 AI 助手入口：抽出共享按钮 `SentenceChatButton`（`lib/features/chatbot/widgets/sentence_chat_button.dart`，显隐开关 + ChatbotConfig 组装单一来源），句子详情页改用共享组件；逐句精听 / 难句跟读 / 难句复习 / 收藏复习 4 个句子级页面 AppBar 挂入口，打开前复用各页设置按钮的「暂停自动推进」逻辑；同句跨页面复用同一会话。全文盲听 / 段落复述维持现状（讲解走句子详情页）。**完成时间**: 2026-07-23
- [x] T14 流式中后端 401（token 过期/服务端判未登录）→ 气泡 inline 登录引导：新增 `ChatMessageStatus.authRequired`，`_mapRunError` 识别 `ChatAuthRequiredException`，气泡 inline「需要登录」入口（onSignIn → ensureSignedInForAction，对齐 quotaBlocked 模式）；发送前未登录仍走既有 gate banner。同时修正 `chatbot_flags.dart` 过期注释（后端端点 2026-07-21 已上线，`kChatbotEnabled=true` 为有意发布态）。**完成时间**: 2026-07-23
- [x] T15 学习计划页复习轮次标题左侧图标改为固定 SVG：新增通用 `assets/icon/refresh.svg`（来自 `readable-svg-icons/icons/refresh.svg`），替换 `LearningPlanScreen` 中的 `🔁` emoji，避免不同平台 emoji 字体渲染成蓝色圆角方块；图标颜色跟随轮次状态（完成绿、当前正文色、未来弱化）；完成态 `✅` emoji 改为 `assets/icon/check-circle-3.svg`，当前到期态 `📖` emoji 改为 `assets/icon/calendar-2.svg`，锁定态 `🔒` emoji 改为 `assets/icon/lock.svg`；「立即解锁」按钮新增 `assets/icon/unlock.svg`；补充 widget 回归断言。**完成时间**: 2026-07-23
- [x] T16 修复 AI 回答流结束时 Flutter 文本选择调度抛 `ConcurrentModificationError`：流式生成期间使用不可选中的 Markdown，避免动态 selectable 子节点在帧末更新时重入；回答完成、停止或进入错误终态后再挂载 `SelectionArea`，恢复局部复制与「问 AI」；补充 streaming → done 选择能力切换 widget 回归。**完成时间**: 2026-07-27
- [x] T17 AI 回答与句子正文移动选区体验对齐：两套官方选区补齐为相同的“选择轻反馈 + 平台长按反馈”，修复 iOS 句子首次未聚焦长按无反馈；AI 回答在长按新选区阶段使用 Flutter 自适应放大镜，松手/取消即清理，已有手柄拖动仍交给框架，保留跨 Markdown 块选择和句子查词。句子继续使用 `BoxHeightStyle.tight`；Flutter 3.41.5 的 `SelectionArea` 高亮高度硬编码为 `max`，稳定方案不 fork framework。**完成时间**: 2026-07-27
- [x] 2026-07-23 22:19：设置页 SVG viewBox 规范化。将设置页实际使用的 18 个 SVG 根 `viewBox` 统一为 `0 0 24 24`，并通过 `transform` 映射旧坐标系，避免 Flutter 外层 26x26 绘制时因资源坐标系差异导致视觉尺寸不一致；补充设置页测试断言所有设置页 SVG 图标均声明 `width="24"`、`height="24"`、`viewBox="0 0 24 24"`、根属性不重复且不再包含内联样式块；补跑 `xmllint` 确认 SVG XML 可解析。

### P1

- [ ] 启动埋点附带 4 类授权状态：仅剩手动验证（PostHog Live Events / Persons / Insights）。
- [ ] 段落复述页面复用录音识别模块，接入统一录音识别能力。

### P2

- [ ] 计算每个学习任务的预计/实际耗时，并展示在学习页入口。
- [ ] 学习 Tab 点击学习/复习后直接进入学习页面，跳过学习计划页。
- [ ] 学习 Tab 展示“今日完成任务”折叠区。
- [x] 句子查词文本改用系统标准选择：移除自定义手柄和整句长按/右键复制；单击选中单词、显示选区操作条并查词，长按选词并在松手后查询最终选区。**完成时间**: 2026-07-27
  - 已完成（交互完善）：选区紧贴字形、保留字符级自由边界；操作条提供「复制 / 问 AI」，问 AI 打开同句会话并预置引用；选区折叠或失焦时按 owner 关闭对应词典面板。**完成时间**: 2026-07-27
  - 已完成（视觉与样式收口）：操作条为无箭头紧凑圆角胶囊（垂直内边距 4px）；句子正文与 AI 回答复用独立的平台标准选择样式，同时统一背景、光标和手柄色，不回落到 App 品牌主题；iOS / Android 双入口回归覆盖。**完成时间**: 2026-07-27
  - 已完成（选区收藏）：操作条新增「收藏 / 取消收藏」，选中文本按词汇规则归一化后复用 `saved_words` 收藏流程并保存来源上下文，与单词、词组和意群统一管理；操作后保留选区、词典面板和操作条，按钮原地双向切换，「取消收藏」强制保持单行。**完成时间**: 2026-07-27 20:16
- [x] 修复合集详情音频多选模式左右重复显示选择框：移除左侧选择框，每个音频卡片仅保留右侧选择框，并补充位置回归断言。**完成时间**: 2026-07-27 20:19
- [x] 导入编辑优化后的中英文全量文案：替换 en/zh ARB、恢复技术占位符与缺失转录状态文案、重新生成 AppLocalizations，并适配较长英文设置项及相关 UI 回归断言。**完成时间**: 2026-07-27 12:13 EDT
- [x] 清理未使用的 `autoSkipRetellDescription` 本地化键：删除中英文 ARB 文案并重新生成 AppLocalizations。**完成时间**: 2026-07-27
- [ ] 支持自定义背景、背景音。
- [ ] 播放完成音效、任务完成动画与音效。
- [ ] 埋点能力按中国大陆 / 全球环境拆分落地。
- [x] 修复逐句精听横滑切句：与随心听统一标准 `PageView` 单向同步（左滑下一句、右滑上一句）；相邻自动切句采用 320ms 横滑过渡；移除延迟落页与预停止会话，避免旧索引回写拉回新页；盲听、讲解、自动切句和进度条跳句共享 `goToSentence` 单一状态入口。讲解态手势及底部切句改为落页后才提交：过渡中源句保持讲解、目标句显示盲听，取消手势不重置源句；补齐首句自动推进与讲解态延迟提交回归，并清理已禁用标注引导的遗留代码。**完成时间**: 2026-07-28
- [ ] 难句跟读、难句补练复制逐句精听的左滑/右滑切句机制：使用 `PageView` 单向同步，左滑下一句、右滑上一句，并复用统一的切句状态入口与交互语义。
- [x] 精简 PostHog 埋点：新增生产白名单，仅保留核心学习、导入、权限、身份、ASR 诊断和官方合集漏斗；历史调用与本地 usage 统计保持不变。**完成时间**: 2026-07-28
- [x] 学习计划页更多菜单补充「重置学习进度」：已有学习进度时显示红色危险操作，确认后清除进度并提示完成，交互与音频列表菜单一致。**完成时间**: 2026-07-28

## 进行中

### 通用记忆调度基础设施

> 实施规格见 [docs/memory-scheduler-infrastructure-plan.md](./docs/memory-scheduler-infrastructure-plan.md)。本阶段仅建设可复用基础设施，不接入现有收藏、Flashcard 或音频学习计划流程。

- [x] 任务 0：流程登记。在 `PLAN.md` 登记关键 ADR，并建立以下独立实施任务。**完成时间**: 2026-07-26
- [x] 任务 1：领域接口与 Registry。实现领域值对象、命令、结果、异常、算法 adapter 端口，以及代码型 `fsrs.default@1` Profile/Model Registry；补充纯 Dart 单元测试。**完成时间**: 2026-07-26
- [x] 任务 2：FSRS adapter。引入固定版本 `fsrs: 2.0.1`，实现 FSRS adapter 与状态编解码，补充固定时间 golden 测试，并验证第三方依赖只出现在 adapter 边界。**完成时间**: 2026-07-26
- [x] 任务 3：数据库与 Repository。实现 Drift 调度/事件表、v47→v48 迁移、DAO、mapper 和具备事务、幂等、乐观锁的 Repository；补充 DAO 与迁移测试。**完成时间**: 2026-07-26 23:41
- [x] 任务 4：Application facade。实现 `DefaultMemoryScheduler` 的调度、预览、评分、归档、恢复、清除和 Profile 历史重放迁移，并完成 Riverpod 装配与应用层测试。**完成时间**: 2026-07-26 23:58
- [x] 任务 5：接入前验证。补强旧 operationId 过期重放、归档隔离及 Profile 重放状态一致性回归；确保幂等回放优先由 Repository 事务裁决。**完成时间**: 2026-07-26

### 百度网盘跨平台音频导入 V1

- [ ] 任务 1：后端 OAuth 会话（后端仓库实现；当前 Flutter 仓库不伪造生产后端）。
- [x] 2026-07-18 12:28：任务 2：Flutter OAuth 基础设施。新增百度 OAuth DTO、后端 OAuth API client、系统浏览器 launcher、secure storage credential store、credential repository、基础 providers；扩展 ApiLogInterceptor 对 URI query / body / response 中 OAuth 敏感字段统一脱敏；补充 DTO、API、secure storage、refresh single-flight、移动/桌面浏览器打开模式和日志脱敏单测。
- [x] 2026-07-18 16:12：任务 3：百度文件与导入服务。新增百度网盘文件 API client（目录列表、`filemetas` 获取 dlink、带 `access_token` 和 `User-Agent: pan.baidu.com` 下载），独立于自家后端 Dio 并复用日志脱敏；扩展云盘条目/分页/dlink/文件错误模型；新增百度网盘音频导入服务，把下载临时文件交给现有 AudioFinalizationService + AudioRegistrationService，沿用内容指纹去重、cloudDrive 来源记录、合集关联和进度回调；补充列表解析、errno 映射、下载 URL/UA、未授权、格式拒绝、入库与重复清理单测。
- [x] 2026-07-18 16:42：任务 4：Controller 和 Sheet UI。新增百度网盘导入 StateNotifier Controller，覆盖未授权→授权、授权轮询持久化、目录加载、音频过滤、多选、下载导入、取消和完成状态；导入 Sheet 新增 “Import from Baidu Netdisk” 入口，支持授权提示、目录浏览、文件大小展示、目录上级跳转、音频多选、导入进度和完成摘要；复用任务 3 导入服务与现有音频库入库/内容检测链路；补充 Controller 单测并跑通现有导入 Sheet 回归。
- [x] 2026-07-18 16:59：导入 Sheet 网盘入口分层修复。主入口改为通用“从网盘导入 / Import from Cloud Drive”，点击后进入网盘来源选择页，当前展示“百度网盘 / Baidu Netdisk”，再点击才进入百度授权与文件浏览流程；补充 widget 回归，确认主入口不提前展示百度且不会提前触发授权。
- [x] 2026-07-18 17:45：百度网盘导入 Sheet 文案 i18n 收口。移除网盘来源卡片副标题，并把百度授权、目录加载、失败、空目录、导入进度、完成摘要和按钮文案统一接入 AppLocalizations；补充中文加载态 widget 回归，避免 “Loading Baidu Netdisk files...” 在中文环境泄漏。
- [x] 2026-07-18 18:29：百度网盘文件浏览交互优化。文件浏览页改为固定高度，顶部显示当前目录名与父目录返回入口，根目录返回网盘来源列表，子目录返回上一级；支持右滑返回上一级；右上角新增退出百度网盘登录确认并清除本地授权后关闭导入窗口；移除列表区 path / Up 按钮、底部返回按钮和空目录提示卡；目录列表展示所有文件，非音频文件禁选，文件条目显示修改时间和大小；补充 Controller 与 Sheet 回归测试。
- [x] 2026-07-18 19:00：百度网盘导入选择与顶部操作二次优化。顶部返回/关闭/退出统一为圆形图标按钮，右上角新增当前目录全选/取消全选；文件列表元信息与 checkbox 视觉降对比；网盘选择流程支持音频和同名字幕同时选择，批量导入时复用本地 `matchSubtitlesForAudios` 与 `importLocalSubtitle` 入库主干自动挂载字幕；补充 service、controller 和 sheet 回归测试。
- [x] 2026-07-18 19:24：百度网盘导入顶部按钮与标题微调。右上角全选从难理解的图标按钮改为正常字重的短文字按钮，目录标题改为正常字重并降低字号，退出登录保持圆形图标按钮但默认无底色、仅 hover/press 显示反馈；更新中英文文案和 sheet 回归断言。
- [x] 2026-07-18 19:31：百度网盘导入顶部层级继续收口。目录标题进一步降为常规正文级字号和字重，父目录返回文字去掉加粗，返回箭头使用常规尺寸，避免顶部导航区域显得过重。
- [x] 2026-07-18 20:55：百度网盘导入流程对齐本地文件导入。抽出本地/网盘共用的待导入确认列表、进度模型与导入结果模型，百度和本地选中文件后统一展示音频确认列表（同名字幕以 CC 标记），确认后在确认列表内显示导入中、等待、成功、跳过等行状态和整体进度；完成后停留在导入列表内展示成功数量、含字幕数量和跳过数量，重复项在行内弱化展示重复文件名，不再进入单独导入完成页；百度导入完成后不再立即触发音频内容异常检测，改为沿用用户打开音频/管理字幕时的懒检测，避免刚导入误显“音频异常”；补充 service、controller 和 sheet 回归测试。
- [x] 2026-07-18 22:10：收回导入确认列表中混入的删除入口。导入列表改为纯展示组件，不再提供行内删除或滑动删除；保留列表内进度/完成汇总和百度懒检测改动，并更新相关回归测试。
- [x] 2026-07-18 22:38：导入列表状态展示收口。跳过状态图标从复制改为跳过，完成汇总压成单行展示；导入中记录已处理条目，避免已处理行继续显示等待时钟；补充导入 Sheet 与 Controller 回归测试。
- [x] 2026-07-18 23:20：修复导入列表固定高度溢出。共用导入列表在有界高度内把文件列表改为占剩余空间并内部滚动，进度与完成汇总保持可见；无界高度下对列表最大高度做兜底，补充固定高度 widget 回归测试。
- [x] 2026-07-18 23:32：修复导入选择回归。本地文件选择器恢复允许一次选择多个音频/字幕文件，避免选择后确认列表为空；百度网盘恢复完整多选行为，保留全选按钮、方形 checkbox、音频与字幕都可选，删除入口继续移除；补充 picker 参数、网盘多选和 controller 状态回归测试。
- [x] 2026-07-18 23:58：导入列表导航与删除交互修复。导入列表页顶部返回按钮改为只显示返回图标，避免左侧返回文字挤压标题；确认态导入列表恢复待导入音频移除入口，删除仅取消本次选择，导入中和完成态继续保持纯状态展示；补充百度网盘导入列表移除误选音频、顶部返回无文字的 widget 回归测试。
- [x] 2026-07-19 00:12：导入页顶部多选状态修复。返回按钮改为无横线的 iOS 风格返回图标；未选中任何可导入文件时不显示全选，仅保留退出登录入口；选中至少一个音频或字幕文件后进入多选模式，右上角用全选/取消全选替换退出按钮，同时缩小右侧操作区预留宽度，给中间目录标题更多展示空间；补充字幕单选即进入多选、音频选中后全选替代退出和新返回图标回归测试。
- [x] 2026-07-19 00:15：导入结果摘要展示修复。导入完成摘要改为成功与跳过分两行展示；成功导入 0 个音频时不再显示“其中 0 个包含字幕”；重复跳过行和行内跳过状态统一使用警告色 X 图标，避免原跳过图标语义不清；补充重复项摘要 widget 回归测试。
- [x] 2026-07-19 00:28：导入结果字幕统计一致性修复。本地导入完成态新增成功行最终字幕状态映射，行内 CC 与底部“包含字幕”数量统一按真正成功入库的音频结果统计，避免重复项配对字幕污染成功摘要；百度导入完成态行内 CC 也改为按 `importOutcome.addedItems` 的最终字幕状态回显；补充“重复项带字幕、成功项无字幕时摘要不误报字幕”的 widget 回归测试。
- [x] 2026-07-19 08:53：导入列表交互与状态统一修复。本地与百度网盘导入确认页统一为单个主导入按钮，按钮文案按真正导入的音频/同名字幕显示“导入（x 个音频，y 个字幕）”；确认态恢复行内移除误选音频入口；导入进度文案统一为“正在导入 x/y：文件名...”；CC 标记放大，重复跳过改为黄色警示语义；百度批量导入新增逐条完成回调，成功/重复状态可即时回写列表，不再等整批完成；补充列表删除、百度逐条状态、按钮文案与 service/controller 回归测试。
- [x] 2026-07-19 09:56：导入弹窗滚动条控制器修复。共用导入确认列表、重复项列表与百度文件浏览列表改为持有本地 `ScrollController`，`Scrollbar` 和对应 `ListView` 显式共用同一个 controller；导入弹窗外层滚动容器也改为本地 controller 且所有嵌套列表声明 `primary: false`，避免桌面自动滚动条误用无 `ScrollPosition` 的 `PrimaryScrollController` 并触发动画库断言；补充 macOS 平台固定高度列表拖动回归测试。
- [x] 2026-07-19 10:26：本地导入字幕解码插件修复。将 `charset_converter` 2.4.0 作为本地 path override 接入并修补 iOS/macOS 原生 `handle` 分支，已处理 `encode` / `decode` / `check` / `availableCharsets` 后立即返回，避免同名字幕解码时 MethodChannel 重复发送响应并打印 “Message responses can be sent only once”；保留现有多编码字幕解码能力并补跑字幕解码与导入弹窗回归测试。
- [x] 2026-07-19 11:46：导入弹窗网盘 UI 修复。百度网盘未授权连接页不再显示退出登录按钮；导入方式首屏入口改为“本地文件 / 网盘 / 链接”顺序，并收紧入口卡片内边距、图标占位和卡片间距；补充未授权退出按钮隐藏、入口顺序和紧凑间距 widget 回归测试。
- [x] 2026-07-19 12:58：百度网盘导入来源图标替换。将 `~/Downloads/baidu-netdisk.svg` 纳入运行时资源，百度网盘来源卡片改用该 SVG 品牌图标，保留其它导入入口的原有 Material 图标；补跑导入弹窗 widget 回归测试。
- [x] 2026-07-18 21:53：修复合集详情页音频卡片长按无法选中。`AudioListView` 在合集上下文恢复长按进入选择模式，选择模式下点击卡片切换选中状态，`AudioListTile` 支持外层传入选中态并用复选框替代菜单按钮；补充合集音频长按选择 widget 回归测试。
- [ ] 任务 5：跨平台验证与发布准备。

### 启动埋点附带 4 类授权状态

- [x] 任务 1：埋点常量、`PermissionSnapshot` helper、权限 probe 与单测。
- [x] 任务 2：iOS 网络权限 channel 改造，启动时写入本地网络权限快照。
- [x] 任务 3：`AnalyticsChannel.registerSuperProperties`、PostHog 实现与服务转发。
- [x] 任务 4：`main.dart` 启动接入 + Onboarding 权限预告 UI。
- [ ] 任务 5：手动验证 PostHog 数据落库与分析视图。

范围内不做：

- [ ] 不新增教育弹窗。
- [ ] 不调整现有系统权限弹窗时机。
- [ ] 不补 AppLifecycle 恢复监听。
- [ ] 不做 Android 13+ 通知权限专门 UI 验证。

### 录音 + 识别功能

已完成的主干能力：

- [x] 跟读页 live ASR、final transcript 判定、LCS 匹配、录音回放。
- [x] iOS / macOS 原生 live ASR 桥接与统一 session 接口。
- [x] 自动录音、静音自动结束、结果页自动推进。
- [x] 跟读 / 难句补练 / 收藏复习 / 逐句精听 / 全文盲听 / 段落复述共享状态机与骨架收敛。
- [x] 本地 ASR 入口前置检查与下载弹窗。
- [x] iOS `prod` flavor release 构建配置修复。
- [x] 段落复述“关闭评级”开关与回听链路打通。

当前未完成：

- [ ] Android 离线 ASR 结束录音闪退。
- [ ] 段落复述页面复用统一录音识别模块。

## 最近完成（保留近两周）

- [x] 2026-07-27 22:43：修复字幕编辑器缩放滑杆圆点在最左/最右端时难以触摸拖动；移除不参与命中测试的 Slider 显式 padding，保持 7px 圆点视觉尺寸，将 overlay 交互范围扩大到标准 48px；补充左右端点外侧按下并向内拖动的 widget 回归。**完成时间**: 2026-07-27 22:43
- [x] 2026-07-27 22:25：字幕编辑器波形最大缩放从每秒约 2cm 提高到每秒约 5cm，保持每秒约 1cm 的初始缩放不变，便于在拥挤波形中精调字幕边界；更新长音频自适应与缩放钳制回归测试。**完成时间**: 2026-07-27 22:25
- [x] 2026-07-25 20:29：Remote Config 启动异步化。启动期不再同步请求 `/api/v1/client/config`，改为只读取本地缓存（允许过期）或默认配置，避免网络慢/超时阻塞首帧；首帧后继续通过 `RemoteConfigController.startPeriodicRefresh(forceFirst: true)` 后台刷新并更新 provider；Remote Config Dio 不再覆盖 3 秒短连接超时，恢复使用后端默认 15/30 秒；补充启动初始加载、缓存损坏回退和后台刷新回归测试。**完成时间**: 2026-07-25 20:29
- [x] 2026-07-25 20:19：Paywall 权益列表新增优先客户支持。订阅页权益卡新增 “Priority support / 优先客户支持” 文案，未订阅购买态与会员态共用展示；补充英文权益顺序和中文展示 widget 回归测试。**完成时间**: 2026-07-25 20:19
- [x] 2026-07-24 11:43：删除自由播放器方括号字幕历史自动收藏逻辑。首次加载字幕时不再把首尾 `[]` 包裹的字幕句自动加入收藏，也不再剥掉显示文本中的方括号；字幕内容按原文显示，收藏状态只来自用户操作或已有数据库记录；补充首次加载 `[INDISTINCT CHATTER]` 不自动收藏且原样显示的 provider 回归测试。**完成时间**: 2026-07-24 11:43
- [x] 2026-07-24 10:56：Paywall 权益列表新增 AI 助手对话次数。订阅页权益卡新增 “More AI assistant conversations / 更多 AI 助手对话次数” 文案，未订阅购买态与会员态共用展示；补充英文权益顺序和中文展示 widget 回归测试。**完成时间**: 2026-07-24 10:56
- [x] 2026-07-23：修复 GitHub Actions run 30021852357 的 Podcast 详情失败态测试断言。`podcast 合集强刷失败后详情弹窗展示刷新失败状态和时间` 现在断言详情弹窗不显示成功刷新文案，并正向验证失败状态 `Failed · 2026-06-15 11:22`。**完成时间**: 2026-07-23 23:59
- [x] 2026-07-23：收口两个预期异常测试的控制台噪声。`ManageSubtitlesSheet` 本地字幕上传失败测试与 `LocalTranscriptionTaskManager` 转录异常测试保留内存日志断言，但用 zone 截获预期失败路径的 `print` 输出，避免全量测试日志误显错误栈。**完成时间**: 2026-07-23 23:58
- [x] 2026-07-23：修复 GitHub Actions run 30019650741 的 Podcast 合集详情测试失败。`showPodcastFeedInfoSheet` 现在把列表菜单传入的 `refreshStatusText` 继续透传给 `_InfoSheet`，让刷新失败状态在 Podcast 详情弹窗中显示，恢复 `Podcast 合集刷新失败时列表显示标记且菜单详情展示失败状态` widget 回归。**完成时间**: 2026-07-23 23:33
- [x] 2026-07-23：版本号升级到 `1.0.27`。**完成时间**: 2026-07-23 23:13
- [x] 2026-07-23：设置页图标视觉尺寸收口。将设置页偏满框的 `refresh.svg`、`lock.svg`、`group.svg`、`trash-bin.svg`、`diskette.svg`、`play-pause.svg` 在 SVG 资源内部增加居中视觉缩放，并补齐 `trash-bin.svg` / `diskette.svg` 的 24x24 根尺寸规范；设置页 leading 保持 32px 占位和 26px SVG 绘制，GitHub 品牌图标单独收紧到 20px；补充设置页回归测试断言资源级缩放与渲染尺寸。**完成时间**: 2026-07-23 22:55
- [x] 2026-07-23：学习任务 Tab 分组图标替换。将学习任务列表中“待复习”分组标题的 `🔁` emoji 改为固定资源 `assets/icon/refresh.svg`，“首次学习”分组标题的 `🌱` emoji 改为用户指定的 `assets/icon/reading.svg`，复用运行时 assets；补充 StudyScreen widget 回归断言确认旧 emoji 不再渲染且两个 SVG 均出现。**完成时间**: 2026-07-23 22:39
- [x] 2026-07-23：学习计划页首次学习图标改用 reading.svg。将首次学习阶段标题左侧图标从 `assets/icon/book.svg` 改为用户指定的 `assets/icon/reading.svg`，并将该 SVG 纳入运行时 assets；更新 widget 回归断言确认页面使用 reading SVG 且不再渲染叶子 emoji。**完成时间**: 2026-07-23 22:35
- [x] 2026-07-23：设置页列表图标 SVG 替换。将设置页普通用户可见分组中的 emoji leading 图标替换为固定 SVG 资源：账户（`assets/icon/account-1.svg`）、会员与订阅、主题、界面语言、母语、复习提醒、学习设置、语音识别、语音合成、播放设置、词典设置（按要求使用 `assets/icon/locale-1.svg`）、备份与恢复、清空缓存、检查更新、服务条款、隐私政策、写反馈、加入社区；评价入口暂用 Material star 图标。新增 `_settingsSvgIcon` / `_settingsMaterialIcon` 统一尺寸约束，并将运行时所需 SVG 加入 `pubspec.yaml`；`book-shelf.svg` 改为 inline style 以避免 flutter_svg 忽略 `<style>`；补充设置页 widget 回归断言。**完成时间**: 2026-07-23 21:39
- [x] 2026-07-23：主题设置图标替换。主题设置弹窗中的跟随系统、浅色模式、深色模式图标从 emoji 改为 Material 图标 `Icons.brightness_auto_rounded`、`Icons.light_mode_rounded`、`Icons.dark_mode_rounded`，保留原有选择状态和埋点逻辑；补充设置页 widget 回归断言确认新图标存在且旧 emoji 不再渲染。**完成时间**: 2026-07-23 20:47
- [x] 2026-07-23：学习计划页首次学习图标替换。首次学习阶段标题左侧图标从 `🌱` emoji 改为固定资源 `assets/icon/book.svg`，并将该 SVG 纳入运行时 assets，避免平台 emoji 渲染差异；补充 widget 回归断言确认页面使用 book SVG 且不再渲染叶子 emoji。**完成时间**: 2026-07-23 20:36
- [x] 2026-07-23：学习计划页阶段标题行对齐优化。首次学习与复习轮次标题行改用共享列布局，固定标题、状态图标、状态文案、进度计数和展开箭头列，解决有无完成时间/待复习文案时各列上下不齐的问题；`stepProgress` 中英文文案去掉“完成 / completed”后缀，仅显示 `x/y`；补充中文布局列对齐和文案回归测试。**完成时间**: 2026-07-23
- [x] 2026-07-23：学习计划页复习轮次「立即解锁」。锁定中的当前复习轮标题下显示「立即解锁」按钮（免费、一键直接解锁），让用户按自己的节奏提前复习。实现：`learning_progresses` 新增 `manual_unlock_at` 列（v46→v47 迁移），不篡改 `lastStageCompletedAt`——后续轮次仍按本轮实际完成时间顺延；`LearningProgress.nextReviewAt` 解锁后返回解锁时刻（倒计时文案、学习任务页分类、per-audio 通知调度全部自动跟随，原定提醒被 `_cancelStalePerAudioNotifications` 自动取消），`isReviewReadyAt` 对非空 `manualUnlockAt` 无条件短路（规避时光机时间偏差）；跨 stage 推进（完成/跳过）时清除该字段恢复时间锁；`unlockCurrentReview` 带幂等守卫 + 埋点 `review_unlock_early`；暂停中的音频不显示按钮。测试：迁移 fixture、模型解锁/窗口/copyWith、provider 解锁/guard 放行/跨阶段清除/幂等、计划页按钮显隐与点击解锁 widget 回归。UI 调整（同日）：按钮由 `TextButton.icon` 改为浅主色圆角药丸（仅含「立即解锁」主色字，整体可点），倒计时保留在标题行做纯展示 label，与解锁动作分离避免歧义。**完成时间**: 2026-07-23
- [x] 2026-07-23：订阅权益 P1-E6/E8——后端权益信号头 + resume 去盲查（plan §6，P1 收官）。**E6**：`authorizeAiUsage` 仅在配额链路本来就查询权益（开关开启且 client 受限）时把 `entitlementActive` 带回，guard 据此下发 `x-entitlement-active: 1|0` 信号头——**零额外查询、不扩大 DB 故障面**，旁路路径不带头（客户端对无头响应零动作）；放行时各计费 AI 路由把头附到流式/JSON 响应，402 直接带头，401/403 不带；客户端 `EntitlementSignalInterceptor`（`createBackendDio` 统一安装）读头转发，controller 比对分歧后 in-flight 去重 refresh，跳过 `/api/entitlements` 自身。信号头用布尔而非原方案 epoch（客户端本就是与当前 state 比对，见 plan §6 偏差说明）。**E8**：`main.dart` resume 改 `refreshIfStale()`（unknown/isStale/超 5 分钟新鲜窗/越过 expiresAt 才回源）。**状态码反应**：sentence AI 客户端把后端 401 映射为 `AiFeatureAuthRequiredException`（登录引导、不重试），402 维持配额异常 + E7。新增拦截器单测、controller E6 分歧/去重与 E8 新鲜窗/越期用例、后端 guard 信号头与 401 用例、translate 路由成功响应头断言；7 个路由测试补 entitlements mock。
- [x] 2026-07-23：订阅权益 P1-E7——后端配额拒绝触发权益收敛（plan §6 E7，纯客户端）。`SubscriptionController` 新增 `reconcileOnServerQuotaRejection`（本地仍 premium 时才回源对账，free 属正常额度用尽不动作）；经可 override 的 `entitlementQuotaDivergenceHandlerProvider` 注入两个 402 触发点：`SentenceAiNotifier` 新增 `onBackendQuotaRejected` 回调（`_quotaExceptionFor` 确认 402 quota_exceeded 时触发）、转录任务 402 分支直调 handler。新增 controller 收敛/不动作用例、sentence AI 402 触发与非 402 不触发用例、转录 402 信号断言（handler 在转录测试容器默认 no-op，避免实例化真实订阅栈）。
- [x] 2026-07-23：调整 Remote Config 刷新策略。客户端默认 TTL 改为 24 小时；冷启动首帧后后台 force 刷新一次 remote config，避免 VPN/地区变化被旧缓存挡住；回前台继续按 TTL 节流刷新；进入 Paywall 时后台 force 刷新一次，保证支付相关远程开关尽快更新。补充 remote config controller 与 Paywall widget 回归测试。后端 `/api/v1/client/config` 下发 `ttlSeconds=86400` 需在后端仓库同步调整。
- [x] 2026-07-23：修复恢复购买未登录弹窗文案。Paywall 登录门支持按动作传入提示文案，订阅购买继续显示“订阅前请先登录”，恢复购买改为“恢复购买前请先登录”；补充 paywall widget 回归覆盖购买/恢复两条未登录路径。
- [x] 2026-07-23：订阅权益重构 P0——全平台统一单一来源（按 [docs/subscription-single-source-plan.md](./docs/subscription-single-source-plan.md) 实施）。客户端不再做本地权益裁决：`_refreshOnline` 三渠道统一读后端 `/api/entitlements`（服务端已合并 RC + Paddle），删除 RC `currentEntitlement()` 对账路径与 `_applyEntitlement` 乐观解锁；`purchase()`/`restore()` 成交后统一 `_convergeAfterTransaction`（force 回源 + 3 次短重试，绝不报「购买失败」）；`restore()` 改为「先 forced 后端刷新命中即结束，仅商店渠道再 RC restore 认领」，`receiptAlreadyInUseError` 映射为 `PurchaseException.receiptInUse` 并转回源确认（修 Bug1/Bug2/Bug3 与评审缺口 R1/R2）；reconciler 增 30 天离线宽限（仅未到期 premium 缓存，修 R4）；后端 `getUserEntitlementSummaryWithReconcile` 增 `force`（60s 每用户防刷）与 `expiredButActive` 续费边界自动回源（修 R3），route 解析 `?force=1`；Paywall 恢复按钮去 webMode 分流、Paddle 会员显示「刷新会员状态」、购买成交未收敛提示「同步中」（新 l10n 键 `premiumRefreshStatus`/`premiumPurchasePendingSync`）。客户端订阅测试 200 个全过（新增 Bug1/Bug3/Bug3b/R1/R2/receiptInUse/切号竞态/收敛失败/离线宽限/force 参数用例），后端 vitest 35 个全过。
- [x] 2026-07-22 19:45：README 社群区改为小红书二维码。将 `~/Downloads/60733.jpg` 复制并重命名为 `assets/qr/xiaohongshu.jpg`，README 社群区移除微信群入口并保留“小红书”扫码入口。
- [x] 2026-07-22 12:19：发现资源入口与发现合集卡片文案/行数调整。合集列表顶部入口标题由“发现精选资源”改为“发现资源”；发现页官方合集卡片描述限制为 1 行并超出省略，避免长描述撑高卡片。补充入口标题与卡片描述单行省略 widget 回归测试。
- [x] 2026-07-22 12:02：调整发现页播客入口文案与视觉。入口标题由“精选播客 / Curated Podcasts”改为“播客 / Podcasts”，去掉“共 N 个播客...”副标题，避免与当前支持搜索和链接订阅的能力不匹配；入口卡片改回接近普通精选合集卡片的间距和字号，并移除无实际语义的右侧箭头，降低视觉重量；同步 l10n 生成文件并更新发现页入口回归测试。
- [x] 2026-07-22 11:48：统一播客预览页与我的合集播客详情页头部摘要组件。抽出 `PodcastFeedSummaryHeader` 共用封面 + 3 行简介 + 内联「更多」展示，预览页和合集详情页不再各自维护重复 UI；合集详情页头部继续固定在顶部。更新预览页与合集详情页 widget 回归。
- [x] 2026-07-22 11:40：优化播客预览页头部信息密度。预览头部封面右侧不再重复展示播客标题（标题已在 AppBar 展示），简介末尾的「更多」改为内联富文本尾部，不再单独占一行；长简介按可用宽度截断并保留「更多」可见。补充预览页回归断言。
- [x] 2026-07-22 09:07：统一搜索预览与我的合集的 Podcast 详情/单集详情。`PodcastFeedMeta` 扩展 RSS channel 元数据（分类、语言、版权、官网、explicit）并兼容旧 JSON；详情弹窗统一用 RSS meta + Apple Podcasts 来源链接 + RSS 链接渲染，元数据区展示类别和语言，隐藏分级/版权等低价值字段；搜索/精选/预览订阅时保存 Apple Podcasts URL 到 `podcastInputUrl`，同时用已知 RSS feedUrl 拉取内容；单集详情在预览和已订阅合集共用展示口径，并用 feed 封面兜底；播客封面组件收敛为统一 `PodcastCover`，RSS 图加载后替换 placeholder，placeholder 播客图标按封面尺寸放大。补充 parser/model、repository、discovery、preview/info sheet、合集详情与音频列表相关回归测试。
- [x] 2026-07-21：修复播客预览「详情」内容随打开时机不一致的 bug。`_PodcastPreviewHeader` 改为 `ConsumerWidget`，meta 统一从 `podcastPreviewProvider` 读取（单一数据源）：feed 加载后内联头图与详情弹窗都用 feed 完整 meta（作者/完整简介/封面），仅加载中回退 catalog 精简信息，消除「第一次看是 catalog 精简、第二次看是 feed 完整」的差异。补充预览页详情用 feed meta 的回归测试。
- [x] 2026-07-21：修复播客描述丢失段落格式。`PodcastFeedParser._cleanText` 由「块级标签→空格 + 全空白压成单空格」改为「块级标签（p/div/li/br）→换行 + 逐行合并行内空白 + 压缩多余空行」，保留 RSS `<description>` HTML 的段落结构；正文裸链接仍由展示层 `_LinkifiedText` 识别为可点击。更新解析器 HTML 清洗断言为换行分隔。
- [x] 2026-07-21：播客详情/单集列表三处交互收口。①单集卡片去掉右侧 chevron 箭头（卡片整体可点已够）。②详情弹窗链接去掉常驻复制图标，改为桌面右键 / 移动端长按在指针处弹出「复制」菜单（`showMenu`），选择后复制并提示。③详情/单集简介正文中的 http/https 链接渲染为可点击（`_LinkifiedText`：`SelectableText.rich` + `TapGestureRecognizer`，剥离结尾标点，点击外部打开），保留文本可选中。更新 `podcast_info_sheet_test` 覆盖右键/长按复制菜单。
- [x] 2026-07-21：播客统一订阅页三处打磨。①搜索框改为纯占位提示（去掉浮动 label 与 URL 示例，输入即消失，贴搜索框惯用法）。②`podcast_info_sheet` 链接行支持复制：桌面右键 / 移动端长按 + 尾部显式复制按钮，复制到剪贴板并提示 `linkCopied`（新增 `podcast_info_sheet_test`）。③播客单集列表美化并对齐 App 列表卡片风格（圆角封面 56 + 标题 + 日期·时长 + 摘要 + chevron），单集头像优先取 `episode.imageUrl` 缺省回退播客封面；点击单集改为打开单集详情 sheet（`showPodcastPreviewEpisodeSheet`：标题/摘要/发布时间/时长/音频下载链接），取代原「先订阅」拦截弹窗。更新预览页单集点击测试。
- [x] 2026-07-21：统一 Apple 播客搜索与订阅入口为单一全屏页。「发现精选合集 → 播客」与「创建合集 → 订阅 Podcast」两个割裂入口收敛到同一 `PodcastDiscoveryScreen`（新路由 `/podcast-subscribe`，两入口都 push；单集预览 `PodcastPreviewScreen` 下沉为其嵌套子路由 `preview`，extra 带 `_RestoredRoutePopper` 兜底，遵守 §7.17）。页面支持搜索关键词（iTunes Search）、粘贴 http/https 链接（改为**解析成可点 item 后点击才订阅**，去掉旧「订阅此链接」盲订阅卡片）、空查询展示精选（`discoverPodcastsProvider`）；点 item 进单集预览，点「+」订阅后**停留在本页**（`collectionListProvider` 派生已订阅态自动翻「去学习」，支持连续订阅），仅「去学习」跳合集详情。预览 provider `podcast_preview_provider` 迁至 `lib/features/podcast/` 并由 catalog-id 泛化为**订阅输入 URL 驱动**（`PodcastPreviewService.fetchByUrl`），供精选/搜索/链接三种来源共用；订阅仍走单一 `createAndFetch` 主干。删除 `OfficialPodcastListScreen`/`OfficialPodcastPreviewScreen`/`podcastCatalogDetailProvider` 及创建合集弹窗内的 `_PodcastSubscriptionPanel`。新增 discovery/preview 屏幕测试与 fetchByUrl 单测，更新路由与创建合集弹窗回归测试。
- [x] 2026-07-21：优化「订阅 Podcast」弹窗，改造为「搜索 + 精选」发现入口。搜索框接入 Apple 官方 iTunes Search API（新增 `PodcastSearchService` + `podcastSearchResultsProvider`，350ms 防抖、family 天然防竞态），无查询词时复用 `discoverPodcastsProvider` 展示精选播客；输入 http/https 链接自动识别为「订阅此链接」，保留 RSS/Apple 直连订阅能力；列表项抽出公共组件 `PodcastSubscribeTile`/`PodcastCover`，弹窗与全屏精选页共用；订阅统一复用 `createAndFetch` 主干并加登录校验与成功跳转；补充搜索服务解析单测与面板组件测。
- [x] 2026-07-21 11:02：合集列表 item 改为显示“更新于”相对时间。`Collection` 模型补齐 `updatedAt` 并从 Drift 映射；资源库合集副标题复用现有 `formatTimeAgo` 显示刚刚/分钟前/小时前/天前等；添加/移除音频、重命名、播客成功刷新和官方合集内容同步会刷新合集更新时间，置顶和刷新失败不刷新；补充模型、provider、合集列表、播客和官方同步回归测试。
- [x] 2026-07-21 07:25：修复 GitHub Actions run 29760958767 的 chatbot carriers 测试断言。`kChatbotUseFakeApi` 已恢复发布默认 false，测试同步改为验证入口开启但走真实流式 API，避免本地联调临时开关污染 CI。
- [x] 2026-07-21 07:16：AI 聊天助手入口接入 remote config 全球开关。Flutter remote config 新增 `features.aiChatAssistant.enabled`，缺失时默认开启；句子详情页 AI 聊天入口改为编译期开关 `kChatbotEnabled` 与远程开关同时命中才显示，保留本地硬停能力；补充 remote config 解析/provider 和入口门控单测。
- [x] 2026-07-20 23:28：修复 BBC 等播客音频下载失败提示不透明的问题。RSS 解析优先使用 `ppg:enclosureSecure` HTTPS 音频地址；已落库的 BBC HTTP enclosure 下载前自动升级为 HTTPS；播客单集下载失败 SnackBar 追加具体原因，并记录下载失败 URL、Dio 类型和 HTTP 状态；补充 parser、下载服务和列表项 widget 回归测试。
- [x] 2026-07-20 23:18：修复 CI JSON 测试判定对 Flutter runner 收尾噪声过严的问题。GitHub Actions 测试解析现在只把带 `error` payload 的 `testDone failure/error` 判为真实失败；对无错误载荷的 orphan `testDone error` 只输出 warning，避免 `done.success=false` 被污染时误挡已全量通过的测试。
- [x] 2026-07-20 23:04：修复 CI 中 TTS controller 预览竞态单测偶发失败。`previewVoice 同一 speakingKey 连续发音` 用例不再依赖固定 `pumpEventQueue()` 次数，而是等待 fake engine 收到指定数量的合成 gate，避免 CI 机器调度较慢时在首个合成请求入队前误判失败；补跑相关 analyze 与单测。
- [x] 2026-07-20 21:39：补充 AI 转录远程时长限制业务入口回归测试，验证默认允许的 2 分钟音频在远程 1 分钟限制下会被字幕管理弹窗正确拦截并展示远程限制值。
- [x] 2026-07-20 21:12：AI 转录音频限制接入 remote app config。后端 `/api/v1/client/config` 新增 `limits.transcription.maxDurationSeconds/maxUploadBytes` resolved 配置，默认 30 分钟 / 50MB；Flutter remote config 新增 `RemoteTranscriptionLimits` 与 `remoteTranscriptionLimitsProvider`，AI 转录入口的时长和文件大小预校验改为读取远程配置，缺失或非法值回退本地默认；补充 remote config 解析、provider 和后端 route 回归测试。
- [x] 2026-07-26：App 端 AI 转录大文件预压缩。App 端有效上传上限收紧为 25MiB；超过上限时先转为 16kHz / 48kbps / 单声道 AAC 临时 m4a，使用压缩产物的指纹、MIME 和大小上传；压缩失败或产物仍超限时不发起上传。新增“音频压缩中”状态与中英文错误提示；临时文件在完成、失败和取消时清理。未修改后端配置，转录成功后的 44.1kHz / 64kbps 本地转码保持不变；补充 provider、widget 与配置回归测试。
- [x] 2026-07-20 16:37：CI 测试结果判定改按 `testDone` 明细。GitHub Actions 全量测试继续保留 JSON reporter，但不再把 `done.success` 作为唯一失败依据；脚本逐条解析 `testDone`，只有存在 `failure` / `error` 用例才失败，并按 `error` 事件关联打印测试名称、错误和堆栈；没有失败用例且存在 `done` 事件时允许通过，同时上传 `test-results.json` artifact 便于后续排查 Flutter runner 收尾误报。
- [x] 2026-07-20 14:40：订阅管理入口按购买来源解耦。后端权益 `/api/entitlements.source` 现在映射为客户端 `Entitlement.source` 并写入诊断日志；“管理订阅”按有效权益来源分流，Paddle 来源即使运行在 App Store / Google Play 商店包内也打开 Paddle Customer Portal，Apple / Google 来源继续打开对应商店管理页；补充后端 source 映射、商店渠道 Paddle Portal 门控和 Paywall 点击回归测试。
- [x] 2026-07-20 14:20：商店包 Web 支付兜底入口文案调整。将商店包订阅页的 Web 支付兜底入口中文文案改为“商店支付遇到问题？使用网页支付”，英文同步调整为“Store payment not working? Use web checkout”，并更新订阅页回归测试断言。
- [x] 2026-07-20 14:02：AI 讲解开关组 UI 优化。学习设置中的 AI 讲解子开关改为自定义对齐行，使用解析、翻译、意群分割对应图标，统一左侧图标/文案和右侧开关位置，强化总开关与子项层级；子项文案调整为“AI 解析 / AI 翻译 / AI 意群分割”，补充设置页回归测试。
- [x] 2026-07-20 13:54：自动意群分割 loading 状态对齐。将意群自动加载触发收口到 `SentenceAnnotationCard` 内，与解析/翻译共用自动加载路径；意群按钮新增外部 loading 状态，自动显示时按钮会展示 spinner 并禁止重复点击；请求来源透传 automatic / userTap，自动请求继续遵守本地 quota reset，手动点击保持强制弹提醒；补充自动意群按钮 loading 回归测试。
- [x] 2026-07-20 13:46：学习设置 AI 讲解自动显示开关。学习设置新增“自动显示 AI 讲解”总开关（默认开启），开启时显示解析、翻译、意群分割三个子开关；解析和翻译默认自动显示，意群默认不自动显示。句子详情页与逐句精听等现有自动讲解入口改为读取该全局设置，关闭总开关时三类 AI 内容都不自动请求或自动展开，手动点击工具栏仍可正常查看；补充 provider、设置页和讲解视图回归测试。
- [x] 2026-07-20 10:19：商店包 Web 支付兜底入口。会员订阅页在商店包远程开关 `showStoreWebCheckoutFallback` 命中且 Paddle 后端可用时，在主订阅按钮下方展示弱化“商店支付遇到问题？使用网页支付”文字入口；用户切换后重新拉取 Paddle plans 并展示 Web 支付价格，主 CTA 文案不额外改成 Web 支付，下面展示弱化“继续使用商店支付”用于切回；购买动作走 Paddle checkout，登录门、浏览器打开和权益轮询复用现有 direct 链路；补充远程配置解析、展示门控、Paddle plans 数据源切换和 Paywall checkout 回归测试。
- [x] 2026-07-19 15:26：远程 Config 定期刷新。Remote Config provider 从启动期静态值改为可变 StateNotifier，保留 `main.dart` 冷启动安全加载，同时运行期通过 `RefreshCoordinator` 复用 TTL 节流与 inflight 合并；新增直接触网的 `fetchRemote()`，回前台和前台长驻时按 `ttlSeconds` one-shot 定时静默刷新，失败只记录日志并保留旧内存配置；导入弹窗继续通过 `remoteFeatureEnabledProvider(RemoteFeature.cloudDriveImport)` 自动响应开关变化；补充 service/controller/provider 单测并回归导入弹窗远程开关测试。
- [x] 2026-07-19 14:16：远程 Config V1：从网盘导入开关。后端 `/api/v1/client/config` 改为版本化 schema，统一 `countryCode` 为 ISO 3166-1 alpha-2 uppercase，并用集中 registry 按国家解析 `features.cloudDriveImport.enabled`（默认关闭，CN 开启）；Flutter 新增 remote config 模型、TTL 缓存、启动期加载与 provider，导入弹窗通过 `RemoteFeature.cloudDriveImport` 控制“从网盘导入”入口显示，当前 provider 仍只有百度网盘；补充后端路由、Flutter 解析/缓存/service 和导入弹窗显示/隐藏回归测试。
- [x] 2026-07-20：AI 聊天页发送后把新消息滑动置顶（取代 07-20 「取消自动滚动」的决定）。`ChatMessageList` 从 `ListView.builder`+`ScrollController` 改用 `ScrollablePositionedList`：发送后监听「最后一条 user 消息 id」变化，用 `ItemScrollController.jumpTo(index, alignment)` 按 index 把新提问瞬时顶到视口顶部（对齐列表顶 padding），末条消息用 `ConstrainedBox(minHeight: 视口高)` 预留空间承接流式回答；回底浮标改为按 `ItemPositionsListener` 的末尾 0 高度哨兵 item 是否进入视口底部阈值判断（原实现依赖 `ScrollController.position`，SPL 不支持）。新增 `CHAT-SCROLL` 诊断日志（置顶触发/落位、浮标显隐）。补充 ChatView widget 回归：新消息气泡贴顶断言、流式增量后仍钉顶。
- [x] 2026-07-20：修复 AI 聊天页新会话后回底按钮残留。`ChatMessageList` 的回底浮标改为只按滚动几何判断：视口底部之外仍有内容才显示，并监听内容尺寸变化与流式最后一条内容变化同步状态；点击“新会话”后列表收缩，按钮随之消失，生成中内容撑出底部时按钮立即出现。补充 ChatView widget 回归覆盖清空后按钮消失、长 greeting 仍有底部内容时按钮可显示、流式未结束时按钮出现。**完成时间**: 2026-07-20
- [x] 2026-07-20：AI 聊天页取消自动滚动。`ChatMessageList` 不再在首帧、消息新增或流式回答增量时主动滚到底部，用户阅读上文时位置保持不变；保留手动回到底部浮动按钮。补充 ChatView widget 回归，覆盖发送和流式更新不改变当前滚动位置。**完成时间**: 2026-07-20
- [x] 2026-07-19：chatbot 用户消息编辑改版。user 气泡去掉常驻操作栏（复制/编辑），改为长按弹 iOS 风格菜单（复制 + 编辑，带右侧 SVG 图标）；assistant 保持常驻「复制 + 重新生成」不变。点「编辑」进入独立全屏编辑页（`ChatEditScreen`：X 关闭 + 标题「编辑消息」+ 预填输入框 + 发送按钮），关闭=取消、发送=返回新文本，确认后才截断该轮并重发（不再点一下就清空后续消息）。controller：`prepareEdit` 换成 `editAndResend(userId,newText)` + `messageContent(id)`；删除 composer 的 `editRequest` 回填 seam（死代码）；新增 l10n `chatEditTitle`、zh `chatEdit` 改「编辑」。测试：message_bubble 长按菜单、chat_edit_screen 预填/发送/关闭/禁用、controller editAndResend 三态。
- [x] 2026-07-18：合集详情页音频多选删除（仅用户自建合集）。长按任一音频进入多选模式，AppBar 切换为多选工具栏（关闭 / 已选 N / 全选·取消全选 / 删除），支持全选后一键删除；删除弹二选一确认「从合集移除 N 项」/「彻底删除 N 项」，分别复用 `CollectionList.removeAudiosFromCollection`（新增批量方法 + `CollectionDao.removeAudios` 单条 SQL 删 junction、内存 `audioIdsMap` 一次更新）与已有 `AudioLibrary.removeAudioItems`。选中态由 `CollectionDetailScreen` 局部持有透传到 `AudioListView`/`AudioListTile`（新增可选参数，默认关闭，库/播客场景零影响），多选态卡片高亮 + 左侧 Checkbox + `IgnorePointer` 屏蔽右侧播放/菜单，`PopScope` 拦截返回优先退出多选；官方/播客合集不启用。测试：DAO 批量移除边界单测 + 屏幕多选进入/全选/二选一删除/官方合集不启用的 widget 测试。
- [x] 2026-07-18：优化音频导入——多选批量导入 + 同名字幕自动配对 + 字幕统一 SRT 入库（含 LRC）。选择器放行「音频+字幕」并集（Android 用 FileType.any 自过滤，避开多扩展名灰选 bug），用户一次多选音频和同名字幕，App 按去扩展名同名（大小写不敏感、优先级 srt>vtt>lrc）自动配对；配对字幕在有音频时长的入库处统一转 SRT（新增 `parseSupportedSubtitle`/`normalizeSubtitleToSrt`/`importLocalSubtitle`），修掉 VTT 原文直存的隐患。新增 LRC 解析器（`lib/services/lrc_parser.dart`，支持厘秒/毫秒/hh:mm:ss/多标签/offset/元数据跳过，末句结束时间取音频总时长）。新增纯配对逻辑 `subtitle_pairing.dart`（`matchSubtitlesForAudios`/`classifyImportFiles`）。手动上传路径（`uploadTranscriptForAudio`/`ManageSubtitlesSheet`）复用同一入库主干。已选文件行显示「含字幕」徽章，全程 `AudioImport` 诊断日志。
  - **性能**：把「复制到沙盒 + 全文件 SHA256 指纹」从选择阶段延后到点「添加」时（进度条覆盖），选完文件预览秒出。
  - **去重展示**：`AudioRegistrationDuplicate` 增加 `attemptedName`/`existingName`，重复弹窗重设计为限高滚动列表（图标+名称，导入名与已有名不同时标注「与「X」内容相同」），弹窗抽为独立 `DuplicatesSkippedDialog` 便于测试。
  - **测试**：LRC 解析、同名配对/分类、VTT/LRC→SRT 规范化、去重名字段、重复弹窗（大量项不溢出/配对次行）等边界单测与 widget 测试。
- [x] 2026-07-17 19:25：修复多语言字幕导入乱码：新增平台 charset 转换依赖，字幕读取按 BOM / UTF-16 / UTF-8 优先，再尝试 GB18030、Big5、Shift-JIS、EUC-KR、Windows-125x 等常见编码，并结合字幕结构与乱码评分选择结果；上传日志记录实际 charset，保留完整错误展示和 stack trace；补充 UTF-8/BOM/UTF-16/中文/繁中/日文/韩文/Windows-1252 解码与上传日志回归测试。
- [x] 2026-07-17 18:05：客户端落盘日志不再重启后表现为清空：启动时从落盘日志恢复最近 500 条到内存日志页，落盘文件上限由 512KB 提升到 5MB，超过上限时保留尾部；日志页清空同步清空落盘文件，并补充 5MB 截断、重启恢复和清空落盘回归测试。
- [x] 2026-07-17 16:49：开发者选项日志页复制改为分享 `.log` 文件，进入日志页自动写入设备诊断信息（App 版本、平台、屏幕、系统版本、机型等），并在 Android / iOS / macOS 增加轻量设备信息 channel；临时日志分享目录纳入缓存清理白名单，补充日志页分享、设备诊断和临时目录清理回归测试。
- [x] 2026-07-17 15:37：新增导航返回链路诊断日志：监听 GoRouter routeInformationProvider 打印当前 path/uri 并对重复 URI 去重，NavigatorObserver 打印 didPush/didPop/didReplace/didRemove，缺 extra 自动退栈与随心听进入/返回句子详解打印关键节点；补充 go/push/pop 与 Navigator 动作回归测试，便于定位返回栈塌陷和双 pop 问题。
- [x] 2026-07-17 14:04：拆分音频内容异常检测：不再依赖 just_audio 时长判断空音频，改用 FFmpeg 短解码判断损坏/格式不兼容，再用 just_waveform 判断静音；列表、学习页和转录确认弹窗区分损坏与静音提示，弹窗补充文件大小和可检测时长，并允许异常状态重检修正旧误报。
- [x] 2026-07-16 21:52：修复 direct/Paddle 与后端权益 `willRenew` 映射：后端 `/api/entitlements` 统一从 RevenueCat CustomerInfo 与 Paddle scheduled change 派生自动续订状态，App 端打印收到的权益响应并映射 `willRenew`，避免自动续订用户误显示“即将到期”；补充后端状态矩阵与 Flutter 映射回归测试。
- [x] 2026-07-16 20:48：修复 Apple 登录取消后错误退出登录页的问题；认证流程现在只有登录成功才返回上一页或进入“我的”Tab，失败/取消都停留在登录方式选择页，并补充 Apple 取消回归测试。
- [x] 2026-07-16 15:04：降低 direct/Paddle checkout 后权益确认轮询频次：`/api/entitlements` 轮询间隔由 3 秒改为 5 秒，保持总等待约 2 分钟，并补充轮询间隔 widget 断言。
- [x] 2026-07-16 14:39：修复 direct/Paddle 支付等待态深色主题加载圈可见性：等待按钮禁用时保留 Premium 蓝底，spinner 使用蓝底对比色，并补充深色主题 widget 断言。
- [x] 2026-07-16 14:26：简化 direct/Paddle 支付等待态：打开 checkout 后主订阅按钮切换为禁用加载态，移除额外等待 label 与“我已完成支付”按钮，并补充 widget 回归断言。
- [x] 2026-07-16 11:15：收口订阅页顶部优惠高亮条：monthly/yearly 都有 paid intro offer 时只展示 yearly；yearly 不存在但 monthly 存在时展示 monthly；两者都没有可展示优惠时隐藏高亮条，并补充三类 widget 回归。
- [x] 2026-07-16 10:55：统一 monthly/yearly paid intro offer 展示逻辑：套餐卡优惠价后缀改为只按月/年显示 `/first mo` / `/first yr`，补充中英文文案、monthly offer 显示回归与 Paddle monthly intro DTO 映射断言。
- [x] 2026-07-16 10:45：适配后端 Paddle plans 新 DTO：App 请求不再发送 locale；direct 套餐解析移除 title / 旧 intro price 依赖，按 percentage intro offer 推导优惠展示价，并补充 repository 与价格工具回归测试。
- [x] 2026-07-16 09:16：统一 direct/Paddle 与 native 订阅的上层行为：Paddle plans 返回 `introOffer` 时复用 native 同一套 Special offer 展示逻辑；direct 匿名权益对账直接进入 free，不再把无 token 当作 Paddle 在线源错误；补充 paywall 与 controller 回归断言。
- [x] 2026-07-16 08:23：补强 direct/Paddle 订阅全流程关键日志，覆盖套餐加载/重试、checkout 创建与浏览器打开、权益轮询/手动检查、后端权益刷新、Customer Portal 与异常路径，便于定位未登录打开订阅页价格不显示等问题。
- [x] 2026-07-15 23:32：修复原生订阅的“管理订阅”入口，iOS 优先调用 StoreKit 系统订阅管理页，Android 优先打开 Play Store 订阅管理页，并保留平台不可用时的外部链接兜底。
- [x] 2026-07-15 23:04：修复原生恢复购买归属校验，RevenueCat restore 返回的订阅若已绑定其他 Echo Loop 账号则拒绝写入当前账号，并在订阅页提示登录原账号后重试。
- [x] 2026-07-15：direct 渠道由 RevenueCat Web Purchase Link 切换为后端 Paddle 集成；App 展示 Paddle 月付/年付套餐，登录后创建 checkout、等待统一权益生效，并通过 Paddle Customer Portal 管理订阅；App Store / Google Play 的 RevenueCat 购买与恢复路径保持隔离。
- [x] 2026-07-15 12:11：订阅页英文标题由“Echo Loop Membership”改为“Echo Loop Premium”，并补充 paywall 标题回归断言。
- [x] 2026-07-15 10:31：统一 direct/Web 渠道订阅页右上角文案为“恢复购买”，底层仍走后端权益同步，避免“刷新”造成用户困惑。
- [x] 2026-07-15 10:20：调整 direct 渠道订阅页中文 CTA 文案，由“前往安全结账”改为“查看订阅方案”，匹配 RevenueCat 托管页仍会展示套餐选择的实际流程。
- [x] 2026-07-15 09:40：优化 direct 渠道 Web checkout 入口，网页支付 CTA 改为安全结账文案，使用系统内置浏览器容器打开 RevenueCat/Paddle 托管结账页，并补充未登录拦截、打开成功等待权益确认、打开失败提示的 widget 回归测试。
- [x] 2026-07-15 09:07：补充 RevenueCat CustomerInfo 关键诊断日志，覆盖 current/purchase/restore/update 路径，输出 expiresAt、willRenew、productId、active entitlements、RC 用户与订阅明细，并补充摘要/快照回归测试。
- [x] 2026-07-14 22:38：版本号升级到 `1.0.26`。
- [x] 2026-07-14 22:24：修复订阅权益前台长驻跨过 expiresAt 后仍保持 Premium；`SubscriptionController` 根据有效权益到期时间安排一次性 refresh，新权益到来时重排 timer，并补到期刷新/重排/永久权益回归测试。
- [x] 2026-07-14 22:11：收口 Web/direct 渠道恢复购买语义，`SubscriptionController.restore()` 在 Web 渠道转为后端权益刷新，避免误穿透到 `WebPurchaseService.restore()` 抛异常，并补充回归测试。
- [x] 2026-07-14 21:59：修复订阅登出本地清理顺序，登出时先将权益状态置为 free 并清除本地缓存，再 best-effort 解绑 RevenueCat 身份；补充 RC 解绑延迟/失败时本地隔离立即生效的回归测试。
- [x] 2026-07-14 21:44：修复订阅控制器身份绑定竞态，RevenueCat 身份核对完成前不再读取 CustomerInfo，快速切换账号时 refresh 等待最新身份任务，身份失败时不查询/写入旧身份权益缓存，并补充串行化回归测试。
- [x] 2026-07-14 17:35：重构订阅权益来源：App Store / Google Play 客户端以 RevenueCat SDK 为准，Web/direct 读 `/api/entitlements`；购买/恢复不再调用后端 reconcile，Flutter 端移除 `/api/entitlements/reconcile` 客户端接口并补渠道分流回归测试。
- [x] 2026-07-13 21:34：微调随心听与学习页底部播放状态 label 的移动端安全区间距，读取真实 viewPadding 并保留约 16px 底边，避免与 iPhone Home indicator 重叠，同时保持底部留白紧凑。
- [x] 2026-07-13 19:56：修复讲解页自动翻译早于前后句上下文就绪导致写入无上下文缓存 key；自动翻译现在等待上下文稳定后再请求，避免返回页面缓存 miss。
- [x] 2026-07-13 17:13：收紧随心听与学习页底部播放状态 label 到底部的间距，移动端压缩安全区占用，给上方内容更多空间。
- [x] 2026-07-13 16:52：收紧句子讲解页原句与内联翻译之间的垂直间距，并补充组件回归测试。
- [x] 2026-07-13 16:25：修复 CI 字典面板测试桩未覆盖增量 TTS 预热，避免落到真实控制器导致 `_coordinator` 未初始化。
- [x] 2026-07-13 16:01：统一翻译加载态与解析加载态，翻译请求中按钮保留圆形进度，内容区改用单行 AI 骨架屏。
- [x] 2026-07-13 15:42：修复意群手动点击超额后被提醒节流吞掉的问题，三类 AI 按钮手动超额均强制弹订阅提醒。
- [x] 2026-07-13 15:28：更新 AI 免费额度用尽弹窗中英文文案，订阅按钮改为 Upgrade Now / 立即升级。
- [x] 2026-07-13 15:14：修复自动加载解析返回空结果时一直 loading；空解析不落缓存、不计试用，UI 退出加载并允许重试。
- [x] 2026-07-13 15:02：修正 AI quota 本地 reset 只阻断自动加载；用户主动点击始终发起 API，并在成功后清除 reset、超额后更新 reset。
- [x] 2026-07-13 14:18：句子讲解页已登录自动加载翻译/解析；新增 AI quota reset 本地阻断、两周提醒节流和订阅提醒弹窗。
- [x] 2026-07-13 12:05：修复两处单测不稳定/失效断言：iOS release metadata 改为只校验字幕文档类型；TTS 文本预热取消测试改为等待首条真实入队，避免全量跑时序误判。
- [x] 2026-07-13 11:21：修复学习播放器测试 DAO 未实现 `getTranscriptSrt` 导致的 39 个 CI 连锁失败。
- [x] 2026-07-13 10:34：统一播客自动刷新机制；改为启动/回前台静默刷新已订阅播客，修复播客详情强刷失败误提示“订阅失败”。
- [x] 2026-07-13 09:02：调整备份范围，移除离线 ASR/TTS 模型文件，仅保留词典资源，避免备份文件过大；恢复时不再覆盖本机模型。
- [x] 2026-07-13 08:40：优化备份与恢复体验，修复大备份时进度动画卡顿，重做备份完成弹窗布局，并将备份文件后缀改为 `.elbak`。
- [x] 2026-07-13 08:13：优化订阅套餐加载，新增启动预热、会话缓存、静默刷新与 storefront 跨区失效，购买前仍以 SDK 当前套餐为准。
- [x] 2026-07-13 01:15：在“我的 > 其它”新增备份与恢复，支持全量数据、音频字幕、词典备份，本地覆盖恢复及临时文件清理。
- [x] 2026-07-13 00:34：修复 CI 旧版数据库迁移测试；`sentence_ai_cache` 缺表时跳过 v45/v46 缓存清理 SQL。
- [x] 2026-07-12：会员订阅页 logo 改为透明背景 `app-icon-1024-alpha.png`。
- [x] 2026-07-13：版本号升级到 `1.0.25`。
- [x] 2026-07-12：统一设置页订阅入口 Upgrade 徽标样式，改为与订阅页优惠条一致的实底高对比风格。
- [x] 2026-07-12：统一订阅页优惠徽标样式，套餐卡 Save badge 改为与顶部优惠条一致的实底高对比风格。
- [x] 2026-07-12：优化订阅页头图与优惠条视觉，改用 Echo Loop logo、实底高对比优惠条并弱化固定购买区分界线。
- [x] 2026-07-12：微调订阅页购买区间距，拉开套餐项间距、收紧顶部留白并增大 Terms / Privacy 间隔。
- [x] 2026-07-12：优化订阅页紧凑布局，独立首期优惠条，缩短法律链接并移除底部自动续费说明。
- [x] 2026-07-12：订阅页权益文案与底部购买区优化，动态展示平台首期优惠。
- [x] 2026-07-12：修复 Onboarding Survey 深色模式视觉异常。
- [x] 2026-07-12：统一自家后端 API 错误日志。
- [x] 2026-07-12：修复 AI 翻译 / 解析超额后卡加载状态。
- [x] 2026-07-12：平台 + 渠道统一识别，并完成 release 渠道注入。
- [x] 2026-07-12：调整随心听主控制按钮间距。
- [x] 2026-07-12：修复讲解页返回播放器误播与按钮状态错误。
- [x] 2026-07-12：意群快捷 AI lookup。
- [x] 2026-07-12：修复播放器句子正文点击后返回焦点错误。
- [x] 2026-07-11：AI API 启用 HTTP/2 访问层。
- [x] 2026-07-11：句子解析流式接收与缓存失效。
- [x] 2026-07-10：移除流式 AI 词典 `queryType` 协议字段。
- [x] 2026-07-09：订阅页首期促销展示 + Web/Paddle 托管 Paywall。
- [x] 2026-07-07：PDF 导出策略调整（首次提醒 + 选项文案/顺序）。
- [x] 2026-07-07：版本号升级到 `1.0.24`。
- [x] 2026-07-06：更新模块渠道化改造。

## 历史归档

- [2026-07-12 全量任务快照](./docs/tasks-archive/tasks-2026-07-12-full.md)
- [Milestone 2 - 学习流程引擎](./docs/tasks-archive/milestone-2-learning-engine.md)
- [Milestone 3 - 收藏与标注体系 + 体验优化](./docs/tasks-archive/milestone-3-completed.md)
- [Milestone 4 - 功能完善与体验打磨](./docs/tasks-archive/milestone-4-features-and-polish.md)
- [Milestone 5 - 登录认证 / Podcast / 离线 ASR / 字幕编辑器](./docs/tasks-archive/milestone-5-completed.md)

## 维护规则

- 新任务先写到“当前优先级”或“进行中”，不要继续把主文件写成长流水账。
- 大段完成记录写入归档文件，主文件只保留“最近完成”和当前有效事项。
- 里程碑状态变化时同步更新 `PLAN.md`。
