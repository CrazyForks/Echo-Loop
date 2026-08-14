# 通用记忆调度基础设施实施计划

> 文档状态：已完成（基础设施尚未接入现有业务流程）
> 目标版本：数据库 schema `v47 -> v48`  
> 默认调度模型：FSRS，依赖版本固定为 `fsrs: 2.0.1`  
> 本阶段范围：只建设可复用基础设施，不接入收藏句子、收藏词汇、收藏意群或音频学习计划的现有业务流程

## 1. 文档目的

本文是一份可直接交给另一个 AI 或开发者执行的自包含实施计划。实施者不需要重新做架构选型，只需按本文定义的边界、文件清单、接口契约、数据结构、迁移步骤和验收标准完成基础设施。

本功能要解决的核心问题不是“在某个页面里调用 FSRS”，而是建立一套由应用自身拥有、与具体记忆算法解耦的调度领域能力。上层业务只依赖稳定接口；底层可以使用 FSRS 库、替换成其他现成库，或改为自研算法，而不要求收藏句子、词汇、音频等调用方同步重写。

## 2. 当前实现与问题分析

### 2.1 收藏句子复习

当前收藏句子复习由 `BookmarkReviewScreen` 和 `bookmarkReviewProvider` 驱动：

- 加载全部有效收藏句子。
- 先按音频分组，音频组随机排序，组内保持句子索引顺序。
- 一次会话会遍历当前全部收藏句子，完成后可重新乱序“再来一遍”。
- 取消收藏只影响书签数据；没有独立的长期记忆状态。
- 不记录 Again / Hard / Good / Easy 等复习反馈。
- 不计算单句的到期时间、稳定性、难度或下一次间隔。
- 不支持只取“今日到期句子”、预测不同评分的下一次间隔或重放历史。

因此它目前是练习播放流程，不是间隔重复调度系统。

### 2.2 收藏词汇/意群复习

当前 Flashcard 复习由 `FlashcardNotifier` 驱动：

- 支持字母、收藏时间、随机和“智能排序”。
- 智能排序使用应用内简化公式：`期望间隔 = 60 分钟 x 2^practiceCount`，再按超期比例排序。
- 翻到背面即增加 `practiceCount`、累计学习时长并更新 `lastPracticedAt`。
- 倒计时也基于词长和 `practiceCount` 做简单衰减。
- 没有质量评分输入，无法区分忘记、困难、正常和轻松回忆。
- 没有持久化的算法状态、明确的 `dueAt`、历史事件或模型版本。

现有 `practiceCount`、`totalStudyMs`、`viewedBack`、`lastPracticedAt` 是产品统计字段，不应被新调度基础设施直接改义或删除。

### 2.3 主要缺口

现状的共同问题如下：

1. 调度规则散落在具体业务流程中，无法被句子、词汇、音频共同复用。
2. 数据模型与简化算法隐式耦合，没有稳定的应用层契约。
3. 没有逐项模型和配置版本，升级算法会同时影响全部存量数据。
4. 没有可审计的复习事件，无法可靠重算、迁移或排查调度结果。
5. 时间获取、随机扰动和第三方类型若不隔离，会导致测试不稳定且升级成本高。

## 3. 目标与非目标

### 3.1 目标

- 提供与内容类型无关的记忆调度领域模型和服务接口。
- 默认支持 FSRS Profile，并把 `fsrs` 包严格封装在 adapter 内部。
- 每个记忆项固定绑定 `profileId + profileVersion`。
- 支持创建调度、查询到期项、预览四种评分、提交复习、归档、恢复和永久删除。
- 保存模型无关的复习事件，支持审计、诊断和未来独立导出能力。
- 提供明确的事务、一致性、并发和错误处理规则。
- 通过纯 Dart 单元测试和 Drift DAO/迁移测试覆盖核心行为。
- 为未来接入收藏句子、收藏词汇、收藏意群和音频学习计划留下稳定接口。

### 3.2 非目标

本阶段明确不做：

- 不修改收藏 Tab、收藏句子复习、Flashcard 或音频学习计划 UI。
- 不在收藏/取消收藏时自动创建、归档或恢复调度。
- 不把现有书签、收藏词、收藏意群或音频数据回填成记忆项。
- 不改变现有 Flashcard 智能排序、倒计时和练习统计逻辑。
- 不改变现有音频固定复习阶段 `review0 ... review28`。
- 不提供 Profile 设置页面、实验平台、云同步或跨设备冲突合并。
- 不同时实现多个真实记忆算法；只完成稳定接口、默认 FSRS adapter 和可替换基础设施。
- 不向上层暴露任何 `package:fsrs` 类型。
- 不实现每日新卡上限；基础设施只提供按 phase 查询和计数能力，具体上限由未来业务接入层决定。
- 不支持同一内容按听辨、跟读等技能维护多条调度，也不增加 `variant` 字段。

## 4. 方案选择

### 4.1 逐项固定 Profile

采用“逐项固定 Profile”：每条 `memory_schedules` 记录保存 `profileId` 和 `profileVersion`。

Profile 是“算法类型 + 算法配置 + 行为开关”的不可变版本。例如：

- `fsrs.default@1`：默认 FSRS 参数。
- 未来可新增 `fsrs.vocabulary@1`：针对词汇实验的参数。
- 未来可新增 `sm2.default@1`：另一种算法。

`fsrs.default@1` 和未来的 `fsrs.vocabulary@2` 并不是两套业务代码，而是两个明确版本的配置快照。名称只表达用途，真正差异由 Profile 中的模型类型、参数和配置决定。

领域或全局默认值仅用于创建新记忆项。默认值改变后，已有项继续使用其原 Profile；本基础设施不提供存量项的 Profile 重算或改绑能力，避免一次配置切换重排全部用户内容。

### 4.2 独立调度表，不向业务表加算法字段

采用独立的 `memory_schedules` 和 `memory_review_events`，不向 `bookmarks`、`saved_words` 或 `audio_items` 添加 FSRS 字段。

理由：

- 调度属于跨领域能力，不属于任一内容表。
- 同一套 schema 可覆盖句子、词汇、意群和音频。
- 业务内容生命周期与算法状态可以独立演进。
- 避免每增加一种内容类型就复制一套调度字段和迁移逻辑。

### 4.3 应用自有接口 + Adapter

上层只使用 `MemoryScheduler`、`MemorySchedule`、`MemoryReviewEvent` 等应用自有类型。FSRS 适配器负责双向转换第三方库对象。

禁止事项：

- Repository、Provider、Screen 或数据库表中出现 `fsrs.Card`、`fsrs.Rating` 等类型。
- 把第三方对象直接 JSON 序列化后当作唯一持久化格式。
- 让 UI 根据具体算法分支。

### 4.4 事件历史 + 当前快照

采用“当前调度快照 + 只追加复习事件”的组合：

- `memory_schedules` 保存高频查询需要的当前状态和 `dueAt`。
- `memory_review_events` 保存模型无关的评分事实以及应用前后的必要审计信息。
- 日常查询不需要每次重放全部历史。
- 评分事件保留为审计记录，不参与日常查询或存量 Profile 切换。

不采用纯事件溯源，因为移动端每次列表查询都重放历史成本过高；也不采用只有当前快照，因为将失去可迁移和可审计能力。

### 4.5 一个业务内容对应一个调度

使用 `(namespace, subjectId)` 作为业务身份，并建立唯一约束。

- `namespace` 表示内容域，例如未来的 `favorite_sentence`、`saved_word`、`saved_phrase`、`audio_plan`。
- `subjectId` 是该域内稳定、可持久化的字符串 ID。
- 基础设施不解析 `subjectId`，也不建立到具体业务表的外键。
- 同一业务内容当前只允许一个调度；不在本阶段支持“一项多技能、多调度”。
- 不预留 `variant`。若未来出现经过验证的多调度需求，应另行设计身份和迁移，而不是在本阶段引入没有明确业务语义的维度。

不使用跨多张业务表的多态外键，因为 SQLite 无法可靠表达这种外键关系，并会把通用模块绑定到具体内容表。

## 5. 总体架构

依赖方向如下：

```text
Future sentence / vocabulary / audio feature
                    |
                    v
        MemoryScheduler (application facade)
          |                    |
          v                    v
MemoryScheduleRepository   MemoryModelRegistry
          |                    |
          v                    v
       Drift DAO       MemoryModelAdapter interface
                               |
                               v
                       FsrsMemoryModelAdapter
                               |
                               v
                         package:fsrs
```

职责划分：

- `domain/`：稳定值对象、实体、枚举、异常和算法端口；不依赖 Flutter、Riverpod、Drift、FSRS。
- `application/`：编排用例、事务边界、Profile 选择和并发校验。
- `data/`：Drift 行与领域对象映射、查询和原子写入。
- `adapters/fsrs/`：唯一允许导入 `package:fsrs` 的位置。
- `providers/`：只负责依赖装配，不承载调度业务流程。

## 6. 核心领域模型

建议在 `lib/features/memory_scheduler/domain/` 下定义以下不可变类型。所有公开核心逻辑补充中文 Dart doc comment，不使用 `dynamic`、不使用非必要 `as` 强转和 `!`。

### 6.1 标识和值对象

```dart
final class MemorySubjectRef {
  final String namespace;
  final String subjectId;

  const MemorySubjectRef({
    required this.namespace,
    required this.subjectId,
  });
}

final class MemoryProfileRef {
  final String profileId;
  final int profileVersion;

  const MemoryProfileRef({
    required this.profileId,
    required this.profileVersion,
  });
}

final class MemoryProfile {
  final MemoryProfileRef ref;
  final String modelId;
  final Map<String, Object?> parameters;
  final bool enableFuzzing;
}
```

约束：

- `namespace`、`subjectId`、`profileId`、`modelId` 必须非空且去除首尾空白。
- `profileVersion` 必须大于 0。
- `MemorySubjectRef` 和 `MemoryProfileRef` 必须实现基于字段的值相等与稳定 `hashCode`，保证 Set 批量查询和 Registry key 行为正确。
- Profile 一经发布不可原地修改；参数变化必须新增版本。
- `parameters` 在注册时做不可变拷贝并由 adapter 严格校验。
- 默认 Profile 固定为 `fsrs.default@1`。
- FSRS fuzzing 是 Profile 的版本化策略，默认 Profile 开启（`enableFuzzing: true`）。新增 Profile 版本可选择关闭；Profile 变化只影响新建调度，既有调度保留原 Profile、状态和已落库 `dueAt`。
- `modelStateVersion` 是 adapter 状态序列化格式的属性，不属于 Profile；实际版本由 adapter 创建的 state/transition 携带并持久化到 schedule/event。

### 6.2 评分

```dart
enum MemoryRating { again, hard, good, easy }
```

这是上层唯一评分枚举。映射到 FSRS 的 Again / Hard / Good / Easy 只发生在 FSRS adapter 内。

### 6.3 调度状态

```dart
enum MemorySchedulePhase { newItem, learning, review, relearning }
enum MemoryScheduleStatus { active, archived }

final class MemorySchedule {
  final String id;
  final MemorySubjectRef subject;
  final MemoryProfileRef profile;
  final String modelId;
  final int modelStateVersion;
  final MemorySchedulePhase phase;
  final MemoryScheduleStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastReviewedAt;
  final DateTime dueAt;
  final int reviewCount;
  final int lapseCount;
  final int revision;
  final Map<String, Object?> modelState;
  final DateTime? archivedAt;
}
```

说明：

- `dueAt` 是跨模型统一的查询字段，使用 UTC 持久化和比较。
- `modelState` 是 adapter 私有状态的 JSON-compatible map，上层只透传、不解释。
- `modelStateVersion` 描述该 adapter 状态结构版本，与 Profile 版本不是同一概念。
- `revision` 在评分、归档、恢复和 Profile 迁移成功时递增；purge 使用 expected revision 条件删除。
- 新建项的 `dueAt` 默认等于创建时间，表示可立即学习。
- 新建项固定为 `reviewCount == 0 -> newItem`；首次评分后再按 adapter 状态映射 learning/review/relearning。
- 归档项不会出现在到期查询中，但保留完整快照和事件。

### 6.4 复习事件

```dart
final class MemoryReviewEvent {
  final String id;
  final String scheduleId;
  final int sequence;
  final String operationId;
  final MemoryRating rating;
  final bool isLapse;
  final DateTime reviewedAt;
  final Duration? responseTime;
  final MemoryProfileRef profile;
  final String modelId;
  final int modelStateVersion;
  final DateTime dueBefore;
  final DateTime dueAfter;
  final int scheduleRevisionAfter;
  final DateTime createdAt;
}
```

`operationId` 是调用方为一次评分生成的幂等键。`rating`、`reviewedAt`、事件顺序和当时是否发生 lapse 是模型无关的历史事实；`isLapse` 固定定义为“评分前 phase 为 review 且 rating 为 again”。`dueBefore`、`dueAfter`、Profile 和版本用于审计，不作为重放算法的输入来源。事件只追加，不提供常规 update/delete API；只有永久清除整个调度时级联删除。

`reviewCount` 由 application 在每次成功追加评分事件时加 1；`lapseCount` 仅在 `isLapse = true` 时加 1。Adapter 不拥有这两个统计字段，避免 Profile 迁移时把历史统计按目标模型重新解释。

## 7. 稳定接口设计

### 7.1 上层 Facade

```dart
abstract interface class MemoryScheduler {
  Future<MemorySchedule> ensureSchedule(
    EnsureMemoryScheduleCommand command,
  );

  Future<MemorySchedule?> getSchedule(MemorySubjectRef subject);

  Future<List<MemorySchedule>> getSchedules(
    Set<MemorySubjectRef> subjects,
  );

  Stream<MemorySchedule?> watchSchedule(MemorySubjectRef subject);

  Future<List<MemorySchedule>> getDueSchedules(
    DueMemorySchedulesQuery query,
  );

  Stream<int> watchDueCount(DueMemoryCountQuery query);

  Future<MemoryRatingPreviewSet> previewRatings(
    PreviewMemoryRatingsQuery query,
  );

  Future<MemoryReviewResult> review(ReviewMemoryCommand command);

  Future<MemorySchedule> archive(ArchiveMemoryScheduleCommand command);

  Future<MemorySchedule> restore(RestoreMemoryScheduleCommand command);

  Future<void> purge(PurgeMemoryScheduleCommand command);
}
```

### 7.2 输入命令

```dart
final class EnsureMemoryScheduleCommand {
  final MemorySubjectRef subject;
  final MemoryProfileRef? profile;
  final DateTime occurredAt;
}

final class MemoryDueCursor {
  final DateTime dueAt;
  final String id;
}

final class DueMemorySchedulesQuery {
  final Set<String> namespaces;
  final Set<MemorySchedulePhase>? phases;
  final DateTime dueBeforeOrAt;
  final int limit;
  final MemoryDueCursor? after;
}

final class DueMemoryCountQuery {
  final Set<String> namespaces;
  final Set<MemorySchedulePhase>? phases;
  final DateTime dueBeforeOrAt;
}

final class PreviewMemoryRatingsQuery {
  final MemorySubjectRef subject;
  final DateTime reviewedAt;
  final int? expectedRevision;
}

final class ReviewMemoryCommand {
  final MemorySubjectRef subject;
  final MemoryRating rating;
  final DateTime reviewedAt;
  final Duration? responseTime;
  final String operationId;
  final int expectedRevision;
}

final class ArchiveMemoryScheduleCommand {
  final MemorySubjectRef subject;
  final DateTime archivedAt;
  final int expectedRevision;
}

final class RestoreMemoryScheduleCommand {
  final MemorySubjectRef subject;
  final DateTime restoredAt;
  final int expectedRevision;
}

final class PurgeMemoryScheduleCommand {
  final MemorySubjectRef subject;
  final int expectedRevision;
}

```

输入规则：

- application service 的时间必须由调用方或注入的 `Clock` 明确提供，核心逻辑中不得直接散落 `DateTime.now()`。
- `reviewedAt` 不得早于上一条事件时间；默认拒绝乱序写入，避免静默改变历史。
- `responseTime` 为可选遥测事实，必须大于等于零，并设置合理上限校验。
- `operationId` 由调用方为一次用户评分生成，用于幂等重试。
- review、archive、restore 和 purge 的 `expectedRevision` 必填；preview 中该字段可选。旧页面或重复点击不能覆盖更新后的调度。
- `responseTime` 必须位于 0 到 24 小时之间。
- `namespaces` 必须非空；`phases = null` 表示不过滤，非 null 时集合必须非空。
- `limit` 固定为 `1..500`。
- 到期结果固定按 `(dueAt ASC, id ASC)` 排序；cursor 使用同一组类型化字段做 keyset pagination，禁止字符串拼接或解析。
- `getSchedules` 是列表页批量读取入口，缺失项不返回；Repository 内部按 SQLite bind 参数上限安全分批，避免 N+1。
- “今日复习”的调用方负责把设备本地日末换算为 UTC 后传入 `dueBeforeOrAt`；基础设施不自行解释时区或日界。

### 7.3 输出结果

```dart
final class MemoryRatingPreview {
  final MemoryRating rating;
  final DateTime dueAt;
  final Duration interval;
  final MemorySchedulePhase phase;
}

final class MemoryRatingPreviewSet {
  final String scheduleId;
  final int revision;
  final DateTime reviewedAt;
  final MemoryRatingPreview again;
  final MemoryRatingPreview hard;
  final MemoryRatingPreview good;
  final MemoryRatingPreview easy;
}

final class MemoryReviewResult {
  final MemorySchedule schedule;
  final MemoryReviewEvent event;
  final bool wasIdempotentReplay;
}

```

评分预览必须一次返回四个具名评分，UI 不应连续调用四次调度器，也不需要对 Map 结果使用空判断或非空断言。预览是只读操作，不写数据库；真正提交时仍需用 `expectedRevision` 校验，不能假设预览后状态未变化。

### 7.4 算法 Adapter 端口

```dart
final class MemoryModelState {
  final int version;
  final Map<String, Object?> values;
}

final class MemoryModelPreview {
  final MemoryModelState state;
  final MemorySchedulePhase phase;
  final DateTime dueAt;
  final DateTime lastReviewedAt;
}

final class MemoryModelPreviewSet {
  final MemoryModelPreview again;
  final MemoryModelPreview hard;
  final MemoryModelPreview good;
  final MemoryModelPreview easy;
}

final class MemoryModelTransition {
  final MemoryModelState state;
  final MemorySchedulePhase phase;
  final DateTime dueAt;
  final DateTime lastReviewedAt;
}

abstract interface class MemoryModelAdapter {
  String get modelId;
  Set<int> get supportedStateVersions;

  void validateProfile(MemoryProfile profile);

  MemoryModelState createInitialState({
    required MemoryProfile profile,
    required DateTime createdAt,
  });

  MemoryModelPreviewSet preview({
    required MemoryProfile profile,
    required MemoryModelState current,
    required DateTime reviewedAt,
  });

  MemoryModelTransition review({
    required MemoryProfile profile,
    required MemoryModelState current,
    required MemoryRating rating,
    required DateTime reviewedAt,
  });
}
```

`MemoryModelState`、`MemoryModelPreviewSet` 和 `MemoryModelTransition` 都是应用自有类型。state/transition 携带实际 `modelStateVersion`、phase、dueAt 和 lastReviewedAt；Adapter 不输出 reviewCount/lapseCount。application 层负责把算法结果和应用拥有的统计写入领域实体及数据库。

### 7.5 Registry

```dart
abstract interface class MemoryProfileRegistry {
  MemoryProfile get(MemoryProfileRef ref);
  MemoryProfileRef defaultForNamespace(String namespace);
}

abstract interface class MemoryModelRegistry {
  MemoryModelAdapter get(String modelId);
}
```

本阶段采用代码定义、不可变 Registry，不建 Profile 数据库表，也不从 Remote Config 动态修改算法参数。原因是算法参数必须和历史可重放性绑定；远端原地改值会破坏版本语义。

初始注册内容：

```text
Profile: fsrs.default@1
modelId: fsrs
parameters: 完整配置按 §11.2 从 fsrs 2.0.1 源码显式复制并固定
enableFuzzing: true
```

`MemoryProfile.parameters` 中使用固定键 `weights`、`desiredRetention`、`learningStepsSeconds`、`relearningStepsSeconds`、`maximumIntervalDays`；时长分别保存为 `[60, 600]` 和 `[600]`，避免 adapter 再猜单位。`enableFuzzing` 使用 Profile 的独立字段，不在 parameters 中重复保存。注册时拒绝缺键、额外键、错误类型、越界值或非有限数值。

不要只调用第三方库的“当前默认值”而不固化参数，因为依赖升级可能改变默认值。同一 Profile 版本必须永远表示同一组参数。

## 8. 数据库设计

### 8.1 `memory_schedules`

新增 `lib/database/tables/memory_schedules.dart`：

| 列 | Drift/SQLite 类型 | 约束与含义 |
| --- | --- | --- |
| `id` | TEXT | 主键，UUID 字符串 |
| `namespace` | TEXT | 非空，业务域 |
| `subject_id` | TEXT | 非空，业务稳定 ID |
| `profile_id` | TEXT | 非空，如 `fsrs.default` |
| `profile_version` | INTEGER | 非空，> 0 |
| `model_id` | TEXT | 非空，如 `fsrs` |
| `model_state_version` | INTEGER | 非空，> 0 |
| `model_state_json` | TEXT | 非空，adapter 私有 JSON，默认 `{}` |
| `phase` | TEXT | 非空，应用枚举字符串 |
| `status` | TEXT | 非空，`active` / `archived` |
| `due_at` | INTEGER/DateTime | 非空，UTC |
| `last_reviewed_at` | INTEGER/DateTime | 可空，UTC |
| `review_count` | INTEGER | 非空，默认 0 |
| `lapse_count` | INTEGER | 非空，默认 0 |
| `revision` | INTEGER | 非空，默认 0 |
| `created_at` | INTEGER/DateTime | 非空，UTC |
| `updated_at` | INTEGER/DateTime | 非空，UTC |
| `archived_at` | INTEGER/DateTime | 可空，UTC |

约束和索引：

- `UNIQUE(namespace, subject_id)`。
- 到期查询部分索引：`(namespace, due_at, id) WHERE status = 'active'`。
- 跨 namespace 到期查询部分索引：`(due_at, id) WHERE status = 'active'`。
- phase 到期查询部分索引：`(phase, due_at, id) WHERE status = 'active'`。
- Profile 运维索引：`(profile_id, profile_version)`。
- Drift 表通过表级 `customConstraints` 定义所有 CHECK，使 `createAll()` 和迁移创建相同 schema；禁止只在迁移 SQL 中补约束。
- CHECK 覆盖非空字符串、`profile_version > 0`、`model_state_version > 0`、合法 phase/status、active/archived 与 `archived_at` 的一致性，以及 `review_count >= 0`、`lapse_count >= 0`、`revision >= 0`。

### 8.2 `memory_review_events`

新增 `lib/database/tables/memory_review_events.dart`：

| 列 | Drift/SQLite 类型 | 约束与含义 |
| --- | --- | --- |
| `id` | TEXT | 主键，UUID 字符串 |
| `schedule_id` | TEXT | FK 到 `memory_schedules.id`，永久清除时 cascade |
| `sequence` | INTEGER | 单调递增，从 1 开始 |
| `operation_id` | TEXT | 调用幂等键 |
| `rating` | TEXT | `again` / `hard` / `good` / `easy` |
| `is_lapse` | INTEGER/Bool | 本次评分是否为历史 lapse 事实 |
| `reviewed_at` | INTEGER/DateTime | 用户评分发生时间，UTC |
| `response_time_ms` | INTEGER | 可空 |
| `profile_id` | TEXT | 本次评分使用的 Profile |
| `profile_version` | INTEGER | 本次评分使用的 Profile 版本 |
| `model_id` | TEXT | 本次评分使用的模型 |
| `model_state_version` | INTEGER | 本次评分后的状态版本 |
| `due_before` | INTEGER/DateTime | 应用评分前的到期时间 |
| `due_after` | INTEGER/DateTime | 应用评分后的到期时间 |
| `schedule_revision_after` | INTEGER | 本次事务后的 revision |
| `created_at` | INTEGER/DateTime | 事件落库时间，UTC |

约束和索引：

- `UNIQUE(schedule_id, sequence)`，保证历史顺序唯一。
- `UNIQUE(schedule_id, operation_id)`，保证同一调度内重试幂等。
- 查询索引 `(schedule_id, reviewed_at, sequence)`。
- 表级 `customConstraints` CHECK 覆盖：`sequence > 0`、合法 rating、`is_lapse IN (0, 1)`、Profile/state version > 0、`schedule_revision_after > 0`，以及 `response_time_ms IS NULL OR response_time_ms BETWEEN 0 AND 86400000`。

事件表刻意不保存完整第三方 before/after 对象。重放以模型无关的 `rating + reviewedAt` 为输入；当前快照保留 adapter 状态用于日常高效调度。

### 8.3 时间和 JSON 规则

- 所有进入领域层的 `DateTime` 先标准化为 `toUtc()`。
- 数据库读取后也转换成 UTC，不依赖设备当前时区。
- UI 展示时才转本地时区。
- “今日复习”属于调用方产品语义：调用方把本地日末转换为 UTC 并作为 `dueBeforeOrAt` 传入。FSRS 产生的绝对 `dueAt` 不在基础设施内截断到自然日。
- `model_state_json` 使用结构化 `jsonEncode/jsonDecode`，解码后逐字段类型校验；禁止字符串拼接解析。
- 非法 JSON、未知枚举、未知 Profile 或不支持的 state version 必须抛出可识别领域异常并记录关键日志，不得静默回退到默认 Profile。

## 9. Repository 与事务规则

### 9.1 Repository 端口

```dart
abstract interface class MemoryScheduleRepository {
  Future<MemorySchedule?> getBySubject(MemorySubjectRef subject);
  Future<List<MemorySchedule>> getBySubjects(
    Set<MemorySubjectRef> subjects,
  );
  Stream<MemorySchedule?> watchBySubject(MemorySubjectRef subject);
  Future<List<MemorySchedule>> getDue(DueMemorySchedulesQuery query);
  Stream<int> watchDueCount(DueMemoryCountQuery query);
  Future<List<MemoryReviewEvent>> getEvents(String scheduleId);

  Future<MemoryReviewResult> commitReview(
    MemoryReviewCommit commit,
  );

}
```

实现可额外提供 create/archive/restore/purge，但 application 层不得直接拼 Drift 查询。

### 9.2 提交评分事务

`review()` 必须按以下顺序执行：

1. 开启短事务，按 `(namespace, subjectId)` 读取当前 schedule，并按 `(schedule_id, operation_id)` 查询事件；幂等检查不得放在事务外。
2. 若 operationId 命中，校验 rating、reviewedAt、responseTime 与原事件一致；payload 不同抛 `MemoryOperationIdConflictException`。
3. payload 相同且 `schedule.revision == event.scheduleRevisionAfter` 时，用当前 schedule 和原事件返回 `wasIdempotentReplay = true`。
4. payload 相同但事件已不是最新事件时，抛 `MemoryIdempotencyReplayStaleException`；事件没有完整历史快照，不能伪造原 `MemoryReviewResult.schedule`。
5. operationId 未命中时，提交只读短事务；根据 schedule 固定的 Profile/model 获取 adapter，校验 state version、active、expected revision 和 reviewedAt 非递减。
6. 在写事务外完成纯算法计算，得到 transition；application 同时计算新的 reviewCount、isLapse 和 lapseCount。
7. 开启写事务，重新读取 schedule 并再次查询 operationId，覆盖步骤 5 到 6 之间的并发窗口；若命中，重复步骤 2 到 4 的判定。
8. operationId 仍未命中时，基于事务内最新 schedule 再次校验 active、expected revision 和 reviewedAt 非递减。
9. 用 `WHERE id = ? AND revision = ? AND status = 'active'` 更新 schedule；受影响行数不是 1 则回滚并抛并发冲突。
10. 在同一写事务内执行 `SELECT COALESCE(MAX(sequence), 0) + 1 FROM memory_review_events WHERE schedule_id = ?`，用结果作为新事件 sequence；禁止从 reviewCount 推导 sequence。
11. 插入事件并提交写事务，返回新快照和事件。

算法计算是纯函数；写事务只包围第二次一致性检查和必要写入。若 schedule 更新或事件插入任一步失败，二者必须同时回滚。两个相同 operationId 并发提交时，后进入写事务的一方会在第二次查询中命中；若底层仍报告 CAS 或唯一约束冲突，则回滚后再用短事务读取 operation 事件及当前 schedule，并按步骤 2 到 4 返回或抛错。

### 9.3 ensure 语义

`ensureSchedule()` 是幂等创建入口：

- 不存在时使用 command 指定 Profile；未指定则读取 namespace 默认 Profile。
- 已存在且 active 时直接返回，不改变已绑定 Profile。
- 已存在且 archived 时不自动恢复，返回明确的 `MemoryScheduleArchivedException`，由调用方决定是否 restore。
- 并发创建依赖 `(namespace, subjectId)` 唯一约束，冲突后重新读取现有项。
- 不增加 `restoreIfArchived` 开关；恢复是带 expected revision 的显式生命周期操作，不能隐式混入创建入口。

### 9.4 归档、恢复和永久清除

- `archive`：只允许 active 调度；校验 expected revision，保留调度和事件，设置 archived 状态及时间，不改变 Profile 和算法状态，revision 加 1。
- `restore`：只允许 archived 调度；校验 expected revision，恢复 active 并保留原 `dueAt`，revision 加 1。因此过期项会立即出现在到期列表；未来“恢复后重置”必须是独立产品能力，不能隐式重排。
- `purge`：携带 expected revision 并用条件删除物理清除 schedule，通过 FK cascade 删除事件。它不设计幂等 operationId，因为只允许由用户确认的永久删除/清空回收站流程调用；该差异是有意设计。
- 基础设施不监听业务表删除；未来每个接入方必须显式把业务生命周期映射到这三个动作。

## 10. Profile 升级

Profile 升级只注册新版本并切换新建调度的默认引用。既有调度永久保留创建时绑定的 Profile、模型状态和已落库 `dueAt`；基础设施不提供重放事件并改写存量调度的接口。评分事件继续作为审计事实保存，不是 Profile 升级的输入。

## 11. FSRS Adapter 设计

### 11.1 依赖隔离

在 `pubspec.yaml` 增加精确版本：

```yaml
dependencies:
  fsrs: 2.0.1
```

不使用 caret，避免同一 Profile 在未审查情况下因依赖解析改变行为。升级 FSRS 时必须：

1. 阅读包 changelog 和状态/默认参数变化。
2. 保留旧 Profile 和旧 state decoder，确保既有调度可继续读取和评分。
3. 增加 golden transition 测试。
4. 仅在验证后创建新 Profile 版本，不修改 `fsrs.default@1`。

### 11.2 转换职责

`fsrs.default@1` 必须逐项冻结以下完整配置，不能只复制 21 个权重：

```text
parameters:
0.2172, 1.1771, 3.2602, 16.1507, 7.0114, 0.57, 2.0966,
0.0069, 1.5261, 0.112, 1.0178, 1.849, 0.1133, 0.3127,
2.2934, 0.2191, 3.0004, 0.7536, 0.3332, 0.1437, 0.2

desiredRetention: 0.9
learningSteps: [1 minute, 10 minutes]
relearningSteps: [10 minutes]
maximumInterval: 36500 days
enableFuzzing: true
```

创建初始状态时禁止调用 `Card.create()`：该 API 是 async，并使用 `DateTime.now()` 和延迟生成 cardId，会破坏同步 adapter 契约与重放确定性。必须使用普通构造函数并显式传入全部初始值：

```dart
Card(
  cardId: 0,
  state: State.learning,
  step: 0,
  stability: null,
  difficulty: null,
  due: createdAt.toUtc(),
  lastReview: null,
)
```

state codec 逐字段解析并校验 cardId、state、step、stability、difficulty、due 和 lastReview。所有日期必须为 UTC，浮点数必须有限；不得直接依赖第三方 `Card.toMap/fromMap` 作为应用唯一持久化契约。

FSRS adapter 当前创建和输出的 `MemoryModelState.version` 固定为 1，`supportedStateVersions` 至少包含 `{1}`。未来修改 state JSON 结构时必须新增 decoder/version，不能原地改变 version 1 的含义。

`FsrsMemoryModelAdapter` 负责：

- 把 `MemoryRating` 映射为 FSRS rating。
- 把应用 Profile 参数构造成 FSRS 参数/调度器。
- 把应用 `modelState` 解码成 FSRS card 所需状态。
- 调用库生成四评分预览和实际 transition。
- 把结果映射回应用自有 state、phase 和 dueAt；reviewCount/lapseCount 由 application 维护。
- 显式处理 phase 映射：`reviewCount == 0 -> newItem`；首次评分后 FSRS learning/review/relearning 分别映射应用同名 phase。
- 对所有参数、时间和数值执行有限性/范围校验。

FSRS 库 API 以 `2.0.1` 的实际源码为准。实现者应在编码时核对包 API，不要根据其他语言版本或旧版 Dart FSRS 猜测类名；但核对 API 不得改变本文的上层接口。

### 11.3 确定性

- `fsrs.default@1` 开启 fuzzing，与 FSRS 默认策略一致；需要可重复断言精确间隔的测试应使用关闭 fuzzing 的专用 Profile。
- 所有计算显式传入 `reviewedAt`。
- 测试使用固定 UTC 时间。
- 同一初始时间、Profile 和事件序列必须得到相同状态及 `dueAt`。
- 初始 cardId 固定为 0；golden state JSON 必须包含同一确定值。
- 浮点状态持久化不得人工截断；比较测试可使用合理误差，日期结果应精确。

## 12. Provider 与依赖注入

新增 Riverpod provider 只做装配：

- `memoryProfileRegistryProvider`
- `memoryModelRegistryProvider`
- `memoryScheduleRepositoryProvider`
- `memorySchedulerProvider`

Provider 不保存真实调度状态副本，数据库是单一真实来源。未来业务 Provider 可 watch `MemoryScheduler` 查询结果，但不能直接读取 adapter 或 FSRS 类型。

时间、ID 生成器和日志接口通过构造参数注入。时间直接复用项目已有的 `package:clock`，不新增只包装 `now()` 的 `MemoryClock`：

```dart
abstract interface class MemoryIdGenerator {
  String newId();
}
```

生产环境可复用 `uuid` 依赖并注入 `const Clock()`；测试使用递增 ID 和 `Clock.fixed(...)`，所有读取结果调用 `toUtc()`，避免随机和时区失败。

## 13. 文件变更清单

### 13.1 依赖与数据库

- 修改 `pubspec.yaml`：增加 `fsrs: 2.0.1`。
- 运行依赖解析，并提交生成或更新后的 `pubspec.lock`；不手工编辑 lock 内容。
- 新增 `lib/database/tables/memory_schedules.dart`。
- 新增 `lib/database/tables/memory_review_events.dart`。
- 新增 `lib/database/daos/memory_schedule_dao.dart`。
- 生成 `lib/database/daos/memory_schedule_dao.g.dart`。
- 修改 `lib/database/app_database.dart`：注册两张表和 DAO，schema `47 -> 48`，创建索引和迁移。
- 重新生成 `lib/database/app_database.g.dart`。
- 修改 `lib/database/providers.dart`：暴露 DAO provider（若项目现有模式要求）。

### 13.2 领域层

建议新增：

- `lib/features/memory_scheduler/domain/memory_rating.dart`
- `lib/features/memory_scheduler/domain/memory_subject_ref.dart`
- `lib/features/memory_scheduler/domain/memory_profile.dart`
- `lib/features/memory_scheduler/domain/memory_schedule.dart`
- `lib/features/memory_scheduler/domain/memory_review_event.dart`
- `lib/features/memory_scheduler/domain/memory_scheduler_commands.dart`
- `lib/features/memory_scheduler/domain/memory_scheduler_results.dart`
- `lib/features/memory_scheduler/domain/memory_model_adapter.dart`
- `lib/features/memory_scheduler/domain/memory_scheduler_exceptions.dart`

若相邻小类型导致文件碎片化，可在实施时合并到 5 至 7 个职责清晰的文件，但不得把 domain、Drift 和 FSRS 混到同一文件。

### 13.3 Application 与 data

- `lib/features/memory_scheduler/application/memory_scheduler.dart`
- `lib/features/memory_scheduler/application/default_memory_scheduler.dart`
- `lib/features/memory_scheduler/application/memory_profile_registry.dart`
- `lib/features/memory_scheduler/application/memory_model_registry.dart`
- `lib/features/memory_scheduler/application/memory_schedule_repository.dart`
- `lib/features/memory_scheduler/data/drift_memory_schedule_repository.dart`
- `lib/features/memory_scheduler/data/memory_schedule_mapper.dart`

### 13.4 FSRS adapter 与装配

- `lib/features/memory_scheduler/adapters/fsrs/fsrs_memory_model_adapter.dart`
- `lib/features/memory_scheduler/adapters/fsrs/fsrs_state_codec.dart`
- `lib/features/memory_scheduler/config/memory_profiles.dart`
- `lib/features/memory_scheduler/providers/memory_scheduler_providers.dart`
- 生成相应 `.g.dart`（若使用注解 provider）。

### 13.5 测试

- `test/features/memory_scheduler/domain/memory_profile_test.dart`
- `test/features/memory_scheduler/application/default_memory_scheduler_test.dart`
- `test/features/memory_scheduler/application/profile_replay_test.dart`
- `test/features/memory_scheduler/adapters/fsrs/fsrs_memory_model_adapter_test.dart`
- `test/features/memory_scheduler/data/drift_memory_schedule_repository_test.dart`
- `test/database/v47_to_v48_migration_test.dart`

实施阶段不要修改当前 `favorites_screen.dart`、`bookmark_review_provider.dart`、`flashcard_provider.dart`、`saved_words.dart`、`bookmarks.dart` 或音频学习计划文件。

## 14. Schema 迁移方案 `v47 -> v48`

1. 把 `AppDatabase.currentSchemaVersion` 从 47 改为 48。
2. 在 `@DriftDatabase` 中注册两张新表和 `MemoryScheduleDao`。
3. `onCreate` 通过 `createAll()` 创建表，并由 `_createCustomIndexes` 创建自定义索引。
4. `onUpgrade` 中 `if (from < 48)` 创建 `memorySchedules`、`memoryReviewEvents`，再创建所有新索引。
5. 新表为空，不回填 `bookmarks`、`saved_words`、`saved_sense_groups` 或 `audio_items`。
6. 迁移测试从 v47 fixture 打开 v48，验证旧数据完整、新表存在、约束和索引生效。
7. 新安装测试验证 `onCreate` 结果与迁移结果 schema 一致。

创建顺序必须先 schedule 后 event；两条创建路径都通过带 `customConstraints` 的 Drift 表定义生成表，再创建相同索引。删除由 FK cascade 控制；迁移和 cascade 测试使用带 `setup: (db) => db.execute('PRAGMA foreign_keys = ON')` 的 `NativeDatabase`，不能照搬未开启 FK 的旧 fixture 写法。迁移 SQL 使用明确表名/列名，不依赖可能变化的第三方对象。

## 15. 错误模型和日志

定义可识别异常，至少包括：

- `MemoryScheduleNotFoundException`
- `MemoryScheduleArchivedException`
- `MemoryScheduleStatusException`
- `MemoryScheduleConflictException`
- `MemoryOperationIdConflictException`
- `MemoryIdempotencyReplayStaleException`
- `MemoryProfileNotFoundException`
- `MemoryModelNotFoundException`
- `MemoryModelStateUnsupportedException`
- `MemoryModelStateCorruptedException`
- `MemoryReviewTimeOrderException`
- `MemoryValidationException`

规则：

- Repository 数据损坏不能伪装成“没有调度”。
- 未知 Profile 不得回退默认 Profile，否则会无声改变存量项算法。
- 幂等 operation 命中是正常结果，不记 error。
- 并发冲突交给上层刷新后重试，不自动覆盖。
- 关键日志包含操作、schedule id、namespace、Profile、revision 和失败阶段；不包含句子、单词或音频正文。

## 16. 测试计划

### 16.1 领域与 Registry

- 非法空 ID、版本、参数类型被拒绝。
- 默认 namespace 返回 `fsrs.default@1`。
- 已发布 Profile 不可变。
- 未知 Profile/model 抛出明确异常。
- 四种评分完整且映射稳定。

### 16.2 FSRS adapter

- 固定初始时间下创建新状态，`dueAt` 合法。
- 初始状态使用普通 `Card` 构造函数、固定 `cardId = 0` 和显式 `due = createdAt`，不调用 `Card.create()`。
- `reviewCount == 0` 映射 newItem；首次评分后 FSRS 三种 State 映射稳定。
- Scheduler 的 21 个权重、desiredRetention、learning/relearning steps、maximumInterval 和 enableFuzzing 全部与 `fsrs.default@1` 固定配置一致。
- Again / Hard / Good / Easy 四预览齐全，输入状态不被修改。
- 四种评分生成合法 transition。
- 固定事件序列得到固定快照和 due date，作为 golden transition 测试。
- state JSON encode/decode 往返等价。
- 非法、缺字段、未知版本 state 被拒绝。
- `package:fsrs` 类型未泄漏到 adapter 目录之外，可用 `rg` 检查。

### 16.3 Application service

- ensure 首次创建和重复调用幂等。
- 默认 Profile 只影响新项；已有项不随默认值变化。
- review 原子更新 schedule 并追加事件。
- 相同 operationId 返回相同结果，不增加计数。
- 相同 operationId 但 payload 不同抛 `MemoryOperationIdConflictException`。
- 已有后续事件时重试旧 operationId 抛 `MemoryIdempotencyReplayStaleException`。
- 两个相同 operationId 并发提交只产生一条事件，后提交者按最新事件幂等返回。
- revision 不匹配抛并发冲突。
- archive 和 restore 均使 revision 加 1，旧页面不能在归档/恢复后继续提交评分。
- 归档项不能 review，且不出现在 due query。
- restore 保留 Profile、state、事件和原 dueAt。
- purge 校验 expected revision，并通过 FK cascade 同时删除事件。
- preview 不产生数据库写入。
- 乱序 reviewedAt 被拒绝。

### 16.4 Profile 升级

- 注册新 Profile 并切换默认值后，新建调度绑定新 Profile。
- 既有调度的 Profile ref、模型状态和 `dueAt` 不变。
- 不存在将存量调度改绑到新 Profile 的公开接口。
- sequence 缺失/重复、Profile 缺失和 revision 冲突均失败。

### 16.5 DAO 与迁移

- `(namespace, subjectId)` 唯一约束。
- `(scheduleId, sequence)` 和 `(scheduleId, operationId)` 唯一约束。
- active 到期项按 `dueAt ASC, id ASC` 稳定排序。
- 单 namespace、跨 namespace、phase 过滤、limit 和类型化 cursor 正确。
- 批量 subjects 查询返回存在项并避免 N+1。
- archived 项被过滤。
- transaction 失败时 schedule/event 同时回滚。
- sequence 使用事务内 `MAX(sequence)+1`，不依赖 reviewCount。
- CHECK 在新安装与 v47→v48 迁移库中一致。
- FK cascade 测试显式开启 `PRAGMA foreign_keys = ON`。
- v47 到 v48 保留所有旧表数据，不产生回填。

### 16.6 UI 与 integration

本阶段没有 UI、路由、平台能力或现有业务流程接入，因此不新增 widget/integration 测试。该项不是遗漏：核心风险由纯 Dart、adapter、application、DAO 和 migration 测试覆盖；未来各业务域接入时再补对应 widget/integration 回归。

## 17. 实施顺序

按以下小步执行，每一步保持可分析、可测试：

1. 在 `PLAN.md` 的关键 ADR 索引登记本基础设施，并在 `TASKS.md` 建立领域接口、FSRS adapter、数据库/repository、application facade 四个独立任务；不为此虚构或改变现有里程碑状态。
2. 新增 domain 值对象、命令、结果、异常和 adapter 端口，先写纯 Dart 测试。
3. 新增代码型 Profile/Model Registry，注册 `fsrs.default@1`。
4. 增加 `fsrs: 2.0.1`，实现 adapter 和 state codec，补固定时间 golden 测试。
5. 新增 Drift 两张表、DAO、mapper、schema v48 迁移和迁移测试。
6. 实现 Repository，包括批量/due 查询、watch、事务写入、幂等和乐观锁。
7. 实现 `DefaultMemoryScheduler` 的 ensure、preview、review、archive、restore、purge。
8. 验证默认 Profile 更新只影响新建调度，存量调度不自动重排。
9. 添加 Riverpod 装配 provider。
10. 运行生成器、格式化、相关 analyze/test，并检查 `package:fsrs` 导入边界。
11. 按子任务逐项更新 `TASKS.md`；只有里程碑状态变化时才更新 `PLAN.md` 里程碑。

本任务较大，实际编码应按仓库“一次一个任务”原则拆成多个可确认任务，建议至少拆为：领域接口、FSRS adapter、数据库与 repository、application facade 四个任务，不要在一个未验证的大改动中一次完成。

## 18. 验证命令

实施阶段按实际改动文件运行，至少包括：

```bash
dart run build_runner build --delete-conflicting-outputs
dart format lib/features/memory_scheduler lib/database test/features/memory_scheduler test/database/v47_to_v48_migration_test.dart
flutter analyze lib/features/memory_scheduler lib/database/app_database.dart lib/database/daos/memory_schedule_dao.dart lib/database/tables/memory_schedules.dart lib/database/tables/memory_review_events.dart
flutter test test/features/memory_scheduler
flutter test test/database/v47_to_v48_migration_test.dart
rg -n "package:fsrs" lib test
git diff --check
```

`rg` 结果应只出现在 `adapters/fsrs/` 及其直接测试中。因为这是跨核心模块和数据库 schema 的基础设施改动，完成全部实施后应运行 `scripts/check.sh`；若当次只完成其中一个独立子任务，则按 AGENTS.md 运行直接相关检查，并在最终整合任务中运行全量检查。

## 19. 验收标准

满足以下全部条件才算基础设施完成：

- 上层存在稳定的 `MemoryScheduler` 接口，接口中无 FSRS 类型。
- `fsrs` 导入被限制在 adapter 和 adapter 测试内。
- 默认 Profile 为不可变的 `fsrs.default@1`，参数显式固定，fuzzing 默认开启；Profile 变更只影响新建调度，存量调度不自动重排。
- 每个 schedule 持久化 `profileId + profileVersion`，默认值变化不影响存量项。
- 能独立创建一个虚拟 namespace/subject 的调度，而无需任何收藏或音频实体。
- 能查询到期项和到期数量，并稳定分页。
- 到期查询支持跨 namespace 和 phase 过滤，列表状态查询支持批量 subjects，且 cursor 为类型化值对象。
- 能一次预览 Again/Hard/Good/Easy 四个结果。
- 能原子提交评分，更新快照并追加模型无关事件。
- operationId 幂等和 revision 乐观锁都有测试。
- reviewCount/lapseCount 由 application 维护，事件固化 `isLapse`，sequence 不依赖统计字段。
- 能归档、恢复、永久清除调度。
- 新 Profile 只影响新建调度，既有调度不会被自动重排或改绑。
- v47 到 v48 迁移不改动、不回填现有收藏和学习数据。
- 现有收藏句子、词汇/意群 Flashcard 和音频学习计划行为完全不变。
- 相关 analyze、unit、DAO、migration 测试通过，最终整合检查通过。

## 20. 未来接入约定

基础设施完成后，各业务域应单独规划接入，不在本计划中实现。建议身份映射如下，但接入前必须确认业务 ID 的长期稳定性：

| 业务 | namespace 建议 | subjectId 建议 |
| --- | --- | --- |
| 收藏句子 | `favorite_sentence` | 优先使用稳定 bookmark UUID；当前自增 id 或 `audioItemId:sentenceIndex` 需先评估同步/重解析稳定性 |
| 收藏词汇 | `saved_word` | 不直接依赖可变显示文本；未来应引入稳定 UUID 后接入 |
| 收藏意群 | `saved_phrase` | 未来稳定 UUID |
| 音频学习计划 | `audio_plan` | `audio_items.id`，但需评估官方内容重装/同步身份 |

每个接入任务至少需要定义：

- 何时 `ensureSchedule`。
- 哪个用户动作对应 Again/Hard/Good/Easy。
- 页面只展示到期项还是允许浏览全部项。
- 取消收藏对应 archive 还是 purge；推荐先 archive，与现有回收站恢复语义一致。
- 恢复收藏时是否恢复原 schedule；推荐 restore，不隐式新建。
- 永久删除/清空回收站时调用 purge。
- 旧统计字段如何继续保留，避免重复计数或指标口径突变。
- “今日复习”的本地日界如何换算成 UTC `dueBeforeOrAt`。
- 每日新项上限如何使用 phase 过滤在产品层实现。

收藏词汇接入时尤其不能把“翻到背面”自动等价为 Good。评分必须来自明确用户反馈或经过产品验证的行为映射，否则即使底层使用 FSRS，输入质量仍会使调度失真。

## 21. 关键维护原则

1. Profile 是不可变发布物，参数变化必须升版本。
2. 算法包升级不等于 Profile 自动升级。
3. 存量项不会因默认值变化而改变，迁移必须显式重放。
4. 数据库存应用稳定字段和 adapter state，不存第三方 Dart 对象。
5. 事件是评分事实，只追加；当前状态是可查询快照。
6. reviewCount/lapseCount 归 application，adapter 只返回算法 state、phase 和 dueAt。
7. 所有时间均以 UTC 进入领域和持久化层；本地日界由调用方转换。
8. 任何未知 Profile、模型或 state version 都显式失败，不静默降级。
9. UI 只依赖 facade，不依赖 DAO、adapter 或具体模型。
10. 先完成基础设施并验证，再按句子、词汇、音频分别接入。
11. 未来若需要云同步，优先同步不可变事件并为 schedule 快照定义派生/冲突策略，不直接采用“最后写入覆盖”合并复习历史。
