# 收藏句通用 Flashcard 复习改造计划

> 状态：Batch 1 与 Batch 2A 已完成；答案、评分与调度接入待后续实施
> 
> 范围：只改造收藏句复习；收藏词汇复习页面及其现有 Flashcard 实现本期保持不变。

## 1. 背景与目标

当前收藏句复习仍是旧的“盲听循环/自动推进 + 可选跟读”流程，入口加载全部有效收藏，按音频分组乱序，不读取通用记忆调度。现有 `MemoryScheduler` 已提供模型无关的 schedule、到期查询、四档评分预览、幂等提交、revision 乐观锁以及 archive/restore/purge。

本计划的目标：

- 建立可复用的调度型 Flashcard 会话内核。
- 让收藏句按 FSRS 调度，只复习 `dueAt <= now` 的项目。
- 用“盲听回忆 -> 显示答案 -> 明确评分 -> 薄弱项补练”替换旧的自动推进主流程。
- 支持音频和视频学习材料；视频卡显示真实视频画面，音频卡显示播放区。
- Again/Hard 评分后显示翻译并进行可配置次数的跟读；翻译、录音、ASR 失败不能阻断复习。
- 未来允许词汇、其他学科或其他学习方式接入同一 Flashcard 内核，而不把内容逻辑塞进通用层。

## 2. 已确定的产品规则

### 2.1 复习队列

- 既有 active schedule 且 `dueAt <= 当前 UTC 时间` 的项目全部进入队列。
- 没有 schedule 的收藏句属于新卡，创建后 `dueAt` 等于创建时刻，因此立即到期。
- 新卡受“每日新句上限”限制，默认 20，可设置为 0-100 或不限；只限制首次引入的新卡，不限制已到期旧卡。
- 当天已引入新卡数量按用户本地日界换算为 UTC，统计 schedule 的 `createdAt`。
- 新卡按收藏时间从旧到新稳定选择；已到期卡按 `dueAt`、稳定 ID 排序，不再按音频组随机。
- 不手工把 Again 卡塞回当前队列；遵循 FSRS learning step。当前队列结束后重新查询，若有新到期项，完成页提供“继续复习”。
- 队列是本次会话快照；评分过程中数据库新增或变更不会重排当前未完成队列。

### 2.2 单卡交互

状态顺序：

`loadingDeck -> prompt -> answer -> submittingRating -> followUp? -> advancing -> completed`

- `prompt`：隐藏英文和翻译，自动播放一次原声；提供重播和“显示答案”。视频材料显示视频画面并关闭可控字幕轨。
- 音频或视频加载失败时显示明确错误、重试和文本降级入口；必要时可使用带“合成语音”标识的 TTS 兜底。
- 未显示答案前，四档评分不可见或不可操作。
- `answer`：显示完整英文句子、来源音频、原声重播、取消收藏入口和评分栏。评分用于判断用户在揭示前对句意的回忆质量。
- 评分定义：Again=没听懂/无法回忆核心意思；Hard=费力或只理解大意；Good=基本一次听懂；Easy=立即且准确地听懂。
- 评分栏显示 Again/Hard/Good/Easy 及 MemoryScheduler preview 的下次间隔，不自行计算间隔。
- Good/Easy 提交成功后直接下一张。
- Again/Hard 提交成功后进入补练，显示英文和翻译，执行句子专属跟读；补练结果不产生第二条 memory review event。
- 翻译优先使用缓存；未缓存时流式请求。翻译失败显示内联错误和重试，但不能阻断播放、录音或继续。
- 跟读次数由设置决定，默认 1 次，范围 1-10。录音成功完成指定次数即可继续，不要求 ASR 达标。
- 用户可跳过跟读；权限拒绝、平台不支持、录音失败和 ASR 失败都提供可解释的跳过路径。

### 2.3 页面布局

- AppBar：关闭、标题、设置；Chat 只在答案或补练阶段显示，避免正面泄露内容。
- 顶部：`n / total`、细进度条、来源音频名称；长名称截断但提供语义标签/tooltip。
- 主体：不使用嵌套卡片。视频使用现有媒体呈现宿主，音频使用固定尺寸播放区；答案和补练内容可滚动。
- 底部：SafeArea 固定操作区。Prompt 只有“显示答案”；Answer 为四档评分；Follow-up 为播放/录音/完成补练。
- 评分按钮宽度稳定；窄屏或大字号自动切换为 2x2，文本不得截断或溢出。
- 不支持横滑评分、上一张修改评分或评分撤销，避免追加审计事件语义不明确。
- 完成页显示已评分数、Again/Hard 数、补练完成/跳过数和剩余到期数；不提供会重复写评分的“再来一遍”。

## 3. 通用 Flashcard 架构

新增独立模块 `lib/features/scheduled_flashcard/`，不得依赖句子、词典、Flutter widget、具体音频引擎或 FSRS 类型。

### 3.1 领域类型

```dart
final class ScheduledFlashcard<T> {
  final MemorySubjectRef subject;
  final T content;
  final int scheduleRevision;
}

sealed class ScheduledFlashcardPhase<T, F> {
  const ScheduledFlashcardPhase();
}

abstract interface class FlashcardDeckSource<T> {
  Future<List<ScheduledFlashcard<T>>> load();
}

abstract interface class FlashcardRatingPort {
  Future<MemoryRatingPreviewSet> preview({
    required MemorySubjectRef subject,
    required int expectedRevision,
    required DateTime reviewedAt,
  });

  Future<MemoryReviewResult> submit({
    required MemorySubjectRef subject,
    required MemoryRating rating,
    required int expectedRevision,
    required DateTime reviewedAt,
    required Duration responseTime,
    required String operationId,
  });
}

abstract interface class FlashcardFollowUpPolicy<T, F> {
  F? followUpFor(T content, MemoryRating rating);
}

enum FollowUpOutcome { completed, skipped, failed }
```

### 3.2 引擎和 controller

- `ScheduledFlashcardEngine<T, F>`：纯 Dart 状态机，负责当前位置、阶段、答案揭示、完成/跳过补练、队列结束，不执行 IO。
- `ScheduledFlashcardController<T, F>`：注入 deck source、rating port、follow-up policy、clock、ID generator；负责异步调用、session/generation token、preview、提交、幂等重试和响应时长。
- `MemorySchedulerFlashcardRatingPort`：将通用接口映射到现有 `MemoryScheduler` 的 `previewRatings` 和 `review`。
- `ScheduledFlashcardSessionState<T, F>`：只暴露当前卡、阶段、进度、preview、错误和补练数据；Provider 只连接它和 UI。
- 异步动作必须在回调落地前检查 session token、card token 和当前 subject；迟到的媒体、翻译、录音或 ASR 结果直接丢弃并记录日志。
- preview 失败时停留在答案面并允许重试；submit 失败不前进。operationId 重放返回幂等结果时正常推进；revision conflict 重新读取 schedule 和 preview，不能重复写事件。

### 3.3 通用 UI

- `ScheduledFlashcardScaffold`：组装通用 AppBar、进度、内容 slot 和底部 slot，不读取业务状态。
- `MemoryRatingBar`：接收四档 preview 和提交回调，处理单排/2x2 几何、loading、disabled、无障碍语义。
- 通用 shell 不创建“万能卡片”或大量 nullable 参数；句子、词汇和其他学科分别提供自己的 prompt/answer/follow-up widget。

## 4. 收藏句适配层

### 4.1 稳定身份和数据库

- Bookmarks 增加不可变 UUID `memorySubjectId`，数据库 schema 升级到 v49。
- 存量 bookmark 在迁移时回填 UUID；新收藏由 DAO/服务生成；软删、恢复和备份恢复保留该 UUID。
- subject 映射固定为 `MemorySubjectRef(namespace: 'saved_sentence', subjectId: memorySubjectId)`。
- 禁止使用句子文本、可变 sentenceIndex 或 `audioItemId:sentenceIndex` 作为长期调度身份。
- 新增 `FavoriteSentenceMemoryLifecycle`，集中处理 ensure、archive、restore、purge 和 reconcile；bookmark DAO 不直接依赖 FSRS adapter。

### 4.2 Deck 和 controller

- `FavoriteSentenceDeckSource` 读取有效 bookmark、关联媒体元数据和已有 schedules，过滤空文本/非法时间。
- 进入会话前先 reconcile：已删除或无对应内容的 schedule 不进入队列；必要时 archive dangling schedule。
- `FavoriteSentenceReviewController` 只负责 Riverpod 装配，所有流程编排下沉到通用 controller 和句子 coordinator。
- `FavoriteSentenceReviewSettings` 独立保存每日新卡上限、跟读次数、播放速度和自动播放；不复用旧的盲听循环/句间倒计时语义。

### 4.3 媒体

- 新增 `FavoriteSentenceMediaCoordinator`，同一时刻只拥有一个 active media session。
- 视频使用 `MediaEngine.loadMedia`、`MediaSentencePlaybackDriver` 和 `PracticeMediaPresentationHost`；音频使用前台音频引擎。
- 跨音频切换、页面销毁、后台、重试和媒体失败均带 generation guard，并释放前一个 session。
- 视频 prompt 隐藏可控字幕轨；硬字幕不做虚假隐藏承诺，日志记录媒体能力而不记录文件路径。
- 原声失败时允许重试、TTS 兜底或纯文本模式，三者均必须有明确 UI 标识。

### 4.4 补练

- `SentenceFollowUpPlan` 至少包含 repetition count、playback speed 和是否需要 translation。
- `SentenceFollowUpPolicy` 仅对 Again/Hard 返回 plan；Good/Easy 返回 null。
- `FavoriteSentenceFollowUpCoordinator` 连接现有 `RepeatFlowEngine`、`SpeechRecordingController`、翻译流和播放驱动。
- 跟读是评分后的学习活动，不写入 MemoryScheduler，不修改 schedule revision。
- 翻译采用 cache-first、streaming fallback；权限、额度、网络和 ASR 失败均转为显式可跳过状态。

## 5. 分批实施顺序

### Batch 1：通用内核

- 新增 scheduled flashcard domain/application/UI shell、MemoryScheduler rating port 和纯 Dart/widget 测试。
- 不修改收藏句、收藏词汇、路由、数据库和现有 Flashcard provider。
- 验收：测试假内容可完成 prompt、answer、四档评分、任意 follow-up 和幂等恢复。

### Batch 2A：手动正面与占位背面（已完成，2026-08-11）

- 收藏入口取消 ASR 权限前置检查，进入极简手动闪卡。
- 正面自动播放一次；上半区可立即中断并重播，下半区无动画切换到空白背面。
- 顶部只展示进度条、学习材料、句子时长和取消收藏；保留 AI 助手与设置占位入口。
- 本批次不接入 MemoryScheduler、评分、答案、视频、翻译或跟读。

### Batch 2：收藏句身份、调度队列和入口

- 完成 v49 bookmark UUID 迁移、lifecycle coordinator、deck source、每日新卡设置和待复习数量。
- 收藏句入口改为只显示到期队列；建立 schedule 的行为必须幂等。
- 验收：存量新卡上限、本地日界、archive/restore/reconcile、无收藏和无到期状态全部通过。

### Batch 3：收藏句 Prompt/Answer、音频/视频和 Good/Easy

- 接入媒体 coordinator、盲听正面、答案面、preview 和四档评分。
- Good/Easy 成功后直接推进；评分失败停留并可重试。
- 验收：音频/视频画面、字幕关闭、媒体切换和调度事件单写入。

### Batch 4：Again/Hard 翻译与跟读

- 接入 translation cache/stream、follow-up policy、跟读次数设置和录音/ASR 降级。
- 验收：Again/Hard 均进入补练；完成或跳过只推进不二次评分；所有权限和失败路径可继续。

### Batch 5：收尾和回归

- 完成完成页、日志/analytics、旧全局收藏句流程清理和专项练习边界确认。
- 检查未使用代码、中文 Dart doc comment、错误状态和日志敏感信息。
- 运行相关 analyze/test、全量收藏词汇回归，并在跨模块迁移完成后运行 `scripts/check.sh`。
- 更新 `TASKS.md`；仅在里程碑实际变化时更新 `PLAN.md`。

## 6. 日志规范

使用 `AppLogger`，固定 tag 为 `ScheduledFlashcard` 和 `FavoriteSentenceReview`，记录：

- session start、有效/无效/孤儿/新卡/到期数量；
- card presented、answer reveal、preview latency；
- rating、operationId、revision、submit latency、success/idempotent/conflict/failure；
- media source、媒体加载失败、translation cache/network/unavailable；
- follow-up start、recording/ASR status、completed/skipped/failed；
- generation stale discard、session exit、session complete。

不得记录句子正文、翻译正文、转录内容、录音内容或绝对文件路径。

## 7. 测试与验收矩阵

- 通用引擎：状态转移、队列完成、空队列、preview/submit 重试、幂等、revision conflict、双击、generation guard、dispose。
- 数据库：v48→v49、UUID 回填、唯一性、新收藏生成、软删/恢复/永久删除。
- 队列：全部 due、每日新卡限制、设置变化、稳定排序、失效内容、无收藏、无到期、重查新到期。
- UI：prompt 隐藏答案、answer 评分门槛、interval 文案、2x2 响应式布局、SafeArea、200% 字体、语义焦点。
- 媒体：音频/视频选择、画面显示、字幕关闭、跨媒体释放、原声失败、TTS/文本降级。
- 补练：翻译缓存和流式失败、权限拒绝、录音失败、ASR 迟到/失败、次数 1-10、跳过路径。
- 回归：收藏词汇复习页面、`/flashcard` 路由和既有测试不得发生行为变化。

## 8. 明确不在本期范围

- 不修改收藏词汇复习页面、`FlashcardItem`、`FlashcardNotifier`、`FlashcardFlowEngine` 和词汇设置。
- 不实现 SM-2 adapter；通用层只依赖现有 `MemoryScheduler`，未来替换算法由基础设施负责。
- 不做云端调度同步；UUID 只保证本地数据库、备份恢复和收藏生命周期稳定。
- 不将 ASR 发音/文本覆盖分数自动转换为 FSRS rating。
- 不把翻译、解析、词典、媒体和录音依赖放进通用 Flashcard 内核。
