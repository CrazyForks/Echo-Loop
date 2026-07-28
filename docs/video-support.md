# 视频内容类型接入 · 两阶段实施计划

## Context

Echo Loop 目前是纯音频学习 App。本计划为 App 新增「视频」内容类型的第一期：打通导入 → 学习计划页 → 视频播放测试页的最小链路，验证视频播放基础能力，不做完整视频学习体验，不破坏任何现有音频功能。

本文档中的所有文件路径、行号、函数签名均已对照当前代码核实，可直接按阶段交付实现，无需再次 plan。两个阶段独立交付：**阶段一**完成导入与占位页，**阶段二**在占位页内实现真实播放能力。

---

## 全局架构决策（两阶段共同前提）

1. **复用 AudioItems 表**，不新建表、不改名、不加列、不升 schema version。
2. **mediaType 不落库**，按 `audioPath` 扩展名派生为计算属性（单一真实来源）。
3. 视频格式白名单只收 **mp4 / mov / m4v**（阶段一按稳定容器选定并已交付；media_kit/libmpv 支持面更广，但本期跳过内容有效性校验，格式选宽会导致「导入成功但播不出来」被误判为 bug，扩白名单属后续需求）。
4. 导入渠道仅本地文件选择器；字幕只走现有同名字幕配对；内容有效性校验（ffmpeg 探测/静音检测）视频全跳过；资源库卡片不做音视频视觉区分。
5. 播放引擎用 **media_kit**（最终目标：media_kit + audio_service 统一音视频播放链路并支持 Windows）。本期两条链路并存：现有 just_audio 音频链路零改动，视频走独立的 media_kit 链路；media_kit 链路稳定后再删 just_audio 链路。新链路组件一律按最终统一架构命名（`Media*` 而非 `Video*`，避免统一时大范围重命名），页面隔着 `MediaPlayerBackend` 接口使用播放器（media_kit 在 flutter test 中不可构造，测试注入 Fake）。
6. 后台播放：视频链路自带媒体会话 handler（`EchoLoopMediaHandler`），经 `MediaSessionRouter`（audio_service 自带 `SwitchAudioHandler`）与现有 `EchoLoopAudioHandler` 共享全 App 唯一的 AudioService 注册位；iOS 进后台断视频轨保音频。不做「交接给 just_audio」。
7. 学习计划页布局不变，视频条目只保证不崩溃；「随心听」按钮对视频条目分流到视频测试页。

关键事实（实现时依赖，已核实）：

- 领域模型 `AudioItem`（`lib/models/audio_item.dart`）**没有** `transcriptSrt` 字段（那是 Drift 表列，`lib/database/tables/audio_items.dart:69`）。页面拿句子列表必须走 `audioSentencesProvider(audioItemId)`（`lib/providers/audio_sentences_provider.dart:31`，内部 `dao.getTranscriptSrt + SubtitleParser.parseSubtitleString`）。
- `getAudioDurationSeconds`（`lib/utils/audio_duration.dart:14`，just_audio 实现）已有 try/catch 返 0 兜底（:21-23），对 mp4 无需任何改动。
- `AudioEngine.loadAudio` 签名为 `loadAudio(AudioItem item, double speed, {String? subtitle})`，返回 `Future<Duration?>`（`lib/providers/audio_engine/audio_engine_provider.dart:104`），内部走 `item.getFullAudioPath()`（:112）并经 `_handler.loadFile` 自动上报锁屏 `MediaItem`（`lib/services/background_audio_handler.dart:280-289`）。
- `AudioEngine.pause()` 会 `sessionId++`（:192-195）；`pauseKeepSession()` 不会（:203-205）；`newSession()`（:449-457）、`isActiveSession(id)`（:459）、`currentPosition`（:44，相对位置，全量加载下等于绝对位置）。
- `audio_item.dart` 已 `import 'package:path/path.dart' as path;`（:2，别名是 `path` 不是 `p`）。

---

# 阶段一：视频导入 + 学习计划页兼容 + 占位测试页

## 1.0 需求与验收标准

- 用户在「添加音频」文件选择器中可选 mp4/mov/m4v 文件，与同名 srt/vtt/lrc 字幕正确配对，正常入库（复用 AudioItems 表，`AudioItem.isVideo == true` 从路径派生）。
- 视频条目在资源库列表正常显示（无视觉区分），点击进入学习计划页：**页面布局不变、不崩溃**、不把视频送入 `listeningPracticeProvider`。
- 学习计划页点「随心听」：视频条目进入一个占位测试页（仅显示标题 + 占位文案）；音频条目行为完全不变。
- 内容有效性校验对视频条目直接跳过（不写入 contentStatus）。
- 所有现有测试全绿（零回归），新增测试覆盖每个改动点。
- **本阶段不引入任何新依赖**（media_kit 属于阶段二）。

## 1.1 MediaType 派生（`lib/models/audio_item.dart`）

在 `TranscriptSource`/`AudioContentStatus` 枚举（:8-50）之后新增：

```dart
/// 支持导入的视频扩展名（小写、不含点）。是 mediaType 判定的唯一依据，
/// 其他文件（如 subtitle_pairing.dart）复用这个常量，不要另外定义一份。
const videoFileExtensions = {'mp4', 'mov', 'm4v'};

/// 媒体类型：按文件扩展名派生，不落库。
enum MediaType { audio, video }

/// 按文件路径扩展名判定媒体类型。path 为 null（未下载/未就绪）或无扩展名时
/// 按 audio 处理——该 fallback 不影响功能，mediaType 只在文件已落盘后被实际读取。
MediaType mediaTypeForPath(String? filePath) {
  if (filePath == null) return MediaType.audio;
  final ext = path.extension(filePath);
  if (ext.isEmpty) return MediaType.audio;
  final normalized = ext.substring(1).toLowerCase();
  return videoFileExtensions.contains(normalized) ? MediaType.video : MediaType.audio;
}
```

`AudioItem` 类内加两个 getter（放 `isAudioReady`（:189）附近；**不是构造参数**，不进 copyWith/toJson/fromJson/数据库映射）：

```dart
/// 媒体类型（按 audioPath 扩展名派生的计算属性，不落库）
MediaType get mediaType => mediaTypeForPath(audioPath);

/// 是否为视频条目
bool get isVideo => mediaType == MediaType.video;
```

## 1.2 导入分类与字幕配对（`lib/features/audio_import/subtitle_pairing.dart`）

该文件现有：`audioImportExtensions = {'mp3','wav','m4a','aac','flac'}`（:9）、`subtitleImportExtensions = {'srt','vtt','lrc'}`（:12）、`ImportFileClassification`（:18-33，字段 `audioNames`/`subtitleNames`/`rejectedExtensions`）、`classifyImportFiles()`（:36-55）、`matchSubtitlesForAudios()`（:64-87）。

改动（import `../../models/audio_item.dart` 拿 `videoFileExtensions`，不新定义常量）：

1. `ImportFileClassification` 加字段 `final List<String> videoNames;`（构造参数同步加）。
2. `classifyImportFiles()`（:40-49 的分类分支）：在 audio 分支后加
   `else if (videoFileExtensions.contains(ext)) { videoNames.add(name); }`，
   保证视频不落进 `rejectedExtensions`。
3. `matchSubtitlesForAudios()`（:72-79）：判定「谁参与同名字幕配对」的条件
   `audioImportExtensions.contains(ext)` 改为
   `audioImportExtensions.contains(ext) || videoFileExtensions.contains(ext)`。
   **这是最容易漏改的点**——漏改则视频永远配不上同名字幕。

## 1.3 导入对话框（`lib/widgets/add_audio_dialog.dart`）

1. `_showAudioFilePicker()`（:626-627）：`final allowed = [...audioImportExtensions, ...subtitleImportExtensions];` 加 `...videoFileExtensions`。
2. `_pickAudioFiles()`（:525-528）：候选文件列表当前只取 `classification.audioNames`，改为同时纳入 `classification.videoNames`（顺序：音频在前视频在后即可）。
3. **不需要改**：`_PickedAudio` typedef（:37-44）不加字段；`_addAudio()`（:828-835）构造 `SandboxedAudioRegistrationInput` 不变；`AudioRegistrationService`（`lib/features/audio_import/audio_registration_service.dart`）整体零改动——`AudioItem(audioPath: input.relativePath, ...)` 落库后 `.isVideo` 自动从路径派生；时长读取已有兜底（见全局关键事实）。
4. 不支持格式报错文案（:593-595，基于 `rejectedExtensions`）语义自然覆盖，零改动。

## 1.4 内容校验跳过（`lib/providers/audio_library_provider.dart`）

`checkAudioContent()`（:477）现有守卫 `if (item == null || !item.isAudioReady) return;`（:482）之后紧接一行：

```dart
if (item.isVideo) return; // 本期视频不做内容有效性校验
```

所有调用方自动继承跳过语义。

## 1.5 学习计划页兼容（`lib/screens/learning_plan_screen.dart`）

initState（:377-423）有两处 `listeningPracticeProvider.notifier.loadAudio` 调用：首次加载（:393-395）和字幕变化监听回调（:415-418，带 `forceTranscriptReload: true`）。提炼私有方法并在两处替换：

```dart
/// 加载音频到听力练习引擎；视频条目本期不接入播放引擎，直接跳过（仅保证页面不崩溃）。
void _maybeLoadAudio(AudioItem item, {bool forceTranscriptReload = false}) {
  if (item.isVideo) return;
  _loadAudioFuture = ref
      .read(listeningPracticeProvider.notifier)
      .loadAudio(item, forceTranscriptReload: forceTranscriptReload);
}
```

安全性已核实，无需新 UI 分支：`_ensureAudioLoaded()`（:428-433）在 `_loadAudioFuture == null` 时 `await null` 直接返回，`lpState.currentAudioItem?.id != widget.audioItemId` 判定为真返回 null；所有调用点都是 `if (lpState == null) return;` 或 `lpState?.xxx ?? 默认值` 模式（如 :782、:879、:593），文件内无任何 `lpState!` 非空断言。

## 1.6 路由 + 占位测试页

### 路由（`lib/router/app_router.dart`）

`AppRoutes` 类新增（跟随 `blindListenPlayer`（:90-93）的统一风格）：

```dart
static const videoTestSegment = 'video-test';

/// 视频播放测试页。collectionId 为 null 时为独立音频变体。
static String videoTest(String? collectionId, String audioId) =>
    collectionId != null
        ? '/collections/$collectionId/$audioId/$videoTestSegment'
        : '/audio/$audioId/$videoTestSegment';
```

新增 GoRoute 挂两处，与现有 7 条音频页（plan/player/blind-listen 等）同构（§7.17 约定：嵌套子路由让 URL 自表达完整栈）：

- 合集内变体：加入 `/collections/:collectionId` 的 `routes:[...]`（:267-375 区间），与 `:audioId/plan`（:285）、`:audioId/player`（:302）平级，path 为 `:audioId/${AppRoutes.videoTestSegment}`。
- 独立音频变体：加入顶层 routes，path 为 `/audio/:audioId/${AppRoutes.videoTestSegment}`（与 :509、:523 的现有顶层变体平级）。

两处均带 `parentNavigatorKey: rootNavigatorKey`；builder 用 `state.extra` 传 `AudioItem`，校验失败返回 `const _RestoredRoutePopper()`——完全照抄 `_pdfPreviewRoute()` 先例（:215-223）：

```dart
builder: (context, state) {
  final item = state.extra;
  if (item is! AudioItem) return const _RestoredRoutePopper();
  return VideoPlaybackTestScreen(audioItem: item);
},
```

### 随心听分流（`learning_plan_screen.dart` `_openFreePlay()`，:454-460）

```dart
void _openFreePlay(BuildContext context) {
  final audioItem =
      ref.read(audioLibraryProvider.notifier).getItemById(widget.audioItemId);
  if (audioItem != null && audioItem.isVideo) {
    context.push(
      AppRoutes.videoTest(widget.collectionId, widget.audioItemId),
      extra: audioItem,
    );
    return;
  }
  if (widget.collectionId != null) {
    context.push(AppRoutes.player(widget.collectionId!, widget.audioItemId));
  } else {
    context.push(AppRoutes.audioPlayer(widget.audioItemId));
  }
}
```

### 占位页（新文件 `lib/screens/video_playback_test_screen.dart`）

阶段一只做占位骨架，**类名、构造签名、文件路径即阶段二的最终形态**，阶段二只替换内部实现：

```dart
/// 视频播放测试页（第一期链路验证）。
/// 阶段一为占位实现；阶段二在本文件内补齐播放能力，构造签名不变。
class VideoPlaybackTestScreen extends ConsumerStatefulWidget {
  const VideoPlaybackTestScreen({super.key, required this.audioItem});
  final AudioItem audioItem;
  ...
}
```

占位 UI：`Scaffold` + AppBar（标题显示 `audioItem.name`）+ 居中文案「视频播放测试页（开发中）」。文案加 ARB（`lib/l10n/app_en.arb` 模板 + zh），键名建议 `videoTestPlaceholder`。

## 1.7 阶段一测试

- `test/models/audio_item_test.dart`（追加）：`mediaTypeForPath` 覆盖 null / 无扩展名 / 音频扩展名 / 三种视频扩展名 / 大写扩展名（`.MP4`）；`AudioItem.isVideo` getter（audioPath 为视频路径 / 音频路径 / null 三态）。
- `test/features/audio_import/subtitle_pairing_test.dart`（追加）：mp4/mov/m4v 分类进 `videoNames`、不进 `rejectedExtensions`；视频与同名字幕配对成功；音频+视频混选时各自正确分类与配对（覆盖 1.2 的两处判定逻辑回归点）。
- `test/providers/audio_library_provider_test.dart`（追加）：对视频条目调用 `checkAudioContent` 直接早退、不写入 contentStatus。
- 学习计划页测试（已有则追加，否则新建最小用例）：pump 视频 AudioItem 的学习计划页不抛异常；`listeningPracticeProvider` 状态的 `currentAudioItem` 未被设为该视频 id。
- `test/router/app_router_test.dart`（追加，照抄 pdf-preview group（:584 起）的模式）：`AppRoutes.videoTest` 两种变体 URI 正确；嵌套结构下深层 URI 重解析后返回不塌栈；extra 丢失命中 `_RestoredRoutePopper`。

回归：`flutter analyze` + `flutter test` 全量跑绿。

## 1.8 阶段一输入/输出边界

- **输入**：用户经文件选择器选择的 mp4/mov/m4v 文件（+可选同名字幕）。
- **输出**：AudioItems 表新纪录（`audioPath` 指向沙盒内视频文件、`transcript_srt` 列含配对字幕正文）；学习计划页可打开；「随心听」到达占位页并收到合法 `AudioItem`（`isVideo == true`、`getFullAudioPath()` 可解析出存在的文件）。
- **交给阶段二的契约**：`VideoPlaybackTestScreen({required AudioItem audioItem})` 构造签名、路由两变体、`audioSentencesProvider(audioItem.id)` 可返回句子列表（有字幕时）。

---


# 阶段二：视频播放测试页实现（media_kit + audio_service，双链路并存）

## 2.0 需求与验收标准

在阶段一占位页内实现（文件不变、`VideoPlaybackTestScreen({required AudioItem audioItem})` 构造签名不变、路由不变）：

1. **播放/暂停**：进入页面自动加载视频（不自动播放），播放/暂停按钮可用。
2. **句子/区间播放**：点击某句从 `startTime` 播到 `endTime` 自动暂停；快速连点只有最后一次生效；手动暂停后不被旧区间终点误暂停。
3. **循环播放**：区间循环（单句 1 次 / 3 次 / ∞，UI 可切）+ 整篇循环开关（∞）；协程照抄 §7.6 确定性模式（一次自然结束只解析一次 await）。
4. **后台播放**：切后台/锁屏音频继续、锁屏出现播放控件（视频链路自己的 handler 经 MediaSessionRouter 上系统媒体会话）；iOS 进后台断视频轨保音频、回前台恢复。
5. **字幕跟随高亮**：播放中当前句高亮（`SentenceTracker.findSentenceIndexByPosition` 纯复用）。
6. **隐藏画面**：开关隐藏视频画面，音频继续播放，再开画面无中断。
7. **硬约束**：`EchoLoopAudioHandler` 类本体、`AudioEngine`、`ForegroundAudioEngine`、`listeningPracticeProvider` 零改动（唯一触点是 `initEchoLoopAudioHandler()` 的 5 行 router 接线）；现有音频功能零回归；本阶段不删 just_audio 任何东西。

## 2.1 架构总览

```
                AudioService.init（全 App 仅一次，main.dart 启动时）
                          │ builder: () => router
                          ▼
          ┌──────────────────────────────────┐
          │ MediaSessionRouter                │ extends SwitchAudioHandler
          │ （audio_service 自带切换原语）      │ lib/services/media_session_router.dart
          │  inner ──┬── 默认: echoHandler    │
          │          └── 视频页: mediaHandler  │ activate()/deactivate() 域语义
          └──────┬──────────────────┬────────┘
                 │(默认)             │(视频页激活期间)
    ┌────────────▼─────────┐  ┌─────▼──────────────────┐
    │ EchoLoopAudioHandler │  │ EchoLoopMediaHandler    │ extends BaseAudioHandler
    │ （零改动）持 just_audio│  │  持 MediaPlayerBackend  │        with SeekHandler
    └────────────▲─────────┘  └─────┬──────────────────┘
                 │                  │ backend getter
    ┌────────────┴─────────┐   ┌────▼───────────────────┐
    │ AudioEngine（零改动） │   │ MediaPlayerBackend 接口 │←─ FakeMediaPlayerBackend(测试)
    └──────────────────────┘   │  └ MediaKitPlayerBackend│←─ media_kit Player+VideoController
                               └────▲───────────────────┘
                                    │ 经 handler 触达（照抄「handler 持 player」模式）
                               ┌────┴───────────────────┐
                               │ MediaEngine (keepAlive) │ sessionId / playRangeOnce / playToEnd
                               └────▲───────────────────┘
                                    │ ref.read(...).notifier；循环协程在页面层
                               ┌────┴───────────────────┐
                               │ VideoPlaybackTestScreen │ Video widget / Offstage / 高亮 / 循环UI
                               └────────────────────────┘
```

四个结构性决策：

- **决策 A：路由层直接 `extends SwitchAudioHandler`，不手写转发。** 已核实 audio_service 0.18.18 源码：`SwitchAudioHandler`（audio_service.dart:2044）的 `set inner`（:2102-2124）取消旧订阅、重订阅新 inner 的 8 条状态流（playbackState/queue/queueTitle/mediaItem/androidPlaybackInfo/ratingStyle/customEvent/customState）；inner 的 subject 是 seeded BehaviorSubject，`.listen` 立即补发当前值 → 切换即刻刷新锁屏。系统回调（play/pause/stop/seek/setSpeed/skip/rewind/fastForward/click/onTaskRemoved/onNotificationDeleted/customAction 等全部 AudioHandler 方法）由父类 `CompositeAudioHandler` 逐方法转发 `_inner.xxx()`，`_inner` 重赋值后自动跟随——不存在需要手工列全的回调清单。
- **决策 B：`EchoLoopMediaHandler` 持 backend、`MediaEngine` 经 handler 操作 backend**——照抄现有「handler 持 player、engine 经 handler 操作」模式（`EchoLoopAudioHandler` 持 `_player`、`AudioEngine` 经 `_handler` :32）。handler 订阅 backend 流做 `_broadcastState`，engine 需要裸流时走 `handler.backend` getter（对应现有 `_handler.player` 用法）。可测试性由 backend 接口保证（media_kit `Player` 在 flutter test 中不可构造）。
- **决策 C：backend/handler 的创建与销毁归 `MediaEngine`（provider 壳 keepAlive，原生资源页面级）。** mpv 实例占内存数十 MB，不随 keepAlive provider 常驻：`loadMedia` 时懒创建（`ensureChain()`）、页面 dispose 时销毁（`disposeChain()`）并交还媒体会话。循环协程放页面层、engine 只提供 session 守卫基元——对齐 `listening_practice_provider._playWholeDriven`（:483）的既有分层。
- **决策 D：命名面向最终统一架构。** 新链路组件一律 `Media*`（`MediaEngine`/`EchoLoopMediaHandler`/`MediaPlayerBackend`…），未来删 just_audio 链路后这套组件直接承接音频播放，避免大范围重命名。只有真正视频特有的概念保留 video 字样（`buildVideoView`、`setVideoTrackEnabled`）；`VideoPlaybackTestScreen`、路由、l10n key 属阶段一既定契约不改。

## 2.2 依赖与初始化

### pubspec.yaml（紧跟 just_audio 附近；media_kit 处于 Limited Maintenance，精确锁版本不带 ^）

```yaml
  media_kit: 1.2.6
  media_kit_video: 2.0.1
  media_kit_libs_video: 1.0.7   # 全 App 统一 video 版 libs，禁止与 media_kit_libs_audio 混用
```

### main.dart（1 行）

`main.dart:71` `WidgetsFlutterBinding.ensureInitialized();` 之后紧跟：

```dart
  if (!kIsWeb) MediaKit.ensureInitialized();   // media_kit 要求在 runApp 前
```

import `package:media_kit/media_kit.dart`。`initEchoLoopAudioHandler()` 调用处（main.dart:170）零改动。

### 平台配置

- iOS/Android/macOS **零新增配置**：audio_service 的 manifest service/receiver、UIBackgroundModes=audio、通知渠道均已就绪；音频会话仍由 `EchoLoopAudioHandler.configureSession()` 的 `speech()` 全局配置一次，视频链路不重复 configure。
- 核对项（pod install 时验证，不算代码改动）：iOS deployment target ≥ 13、macOS ≥ 10.15（media_kit 要求，低了则升，属允许的构建配置调整）。
- **Windows 接口缝（本阶段不实现）**：`MediaPlayerBackend` 平台无关（media_kit 本身支持 Windows）；未来 Windows 的系统媒体控件（SMTC）经 smtc_windows/audio_service_win 做成 router 的平替广播端。本阶段代码不出现任何 `Platform.isWindows` 分支。

## 2.3 媒体会话路由

### 新文件 `lib/services/media_session_router.dart`

```dart
import 'package:audio_service/audio_service.dart';

/// 全 App 唯一注册进 AudioService 的 handler：在默认音频 handler 与视频 handler
/// 之间切换系统媒体会话（锁屏/通知栏归属）。
///
/// 复用 audio_service 的 SwitchAudioHandler：`inner` setter 负责取消/重订阅全部
/// 状态流（BehaviorSubject 补发当前值 → 切换即刻刷新锁屏），系统回调由
/// CompositeAudioHandler 逐方法转发给当前 inner。本类只加两个域语义：
/// 「激活」与「带守卫的交还」（仅当前占用者能交还，防止过期 deactivate 抢会话）。
class MediaSessionRouter extends SwitchAudioHandler {
  MediaSessionRouter({required AudioHandler defaultHandler})
      : _defaultHandler = defaultHandler,
        super(defaultHandler);

  final AudioHandler _defaultHandler;

  /// 当前媒体会话是否被非默认 handler（视频链路）占用。
  bool get isRouted => inner != _defaultHandler;

  /// 把系统媒体会话切给 [handler]。幂等。
  void activate(AudioHandler handler) {
    if (inner == handler) return;
    inner = handler;
  }

  /// [handler] 交还媒体会话给默认 handler。守卫：只有当前占用者能交还，
  /// 旧页面迟到的 deactivate 不会误切走新占用者的会话。幂等。
  void deactivate(AudioHandler handler) {
    if (inner != handler) return;
    inner = _defaultHandler;
  }
}
```

### `lib/services/background_audio_handler.dart` 的精确改动（唯一触点；`EchoLoopAudioHandler` 类零改动，只动文件底部）

1. 顶部加 `import 'media_session_router.dart';`
2. `:444` 附近新增全局：`MediaSessionRouter? _globalMediaSessionRouter;`
3. `initEchoLoopAudioHandler()`（:447-466）：`prepareArtwork()` 之后插 `final router = MediaSessionRouter(defaultHandler: handler);`；`AudioService.init` 的 `builder: () => handler` 改为 `builder: () => router`（config 不动）；`_globalAudioHandler = handler;` 后加 `_globalMediaSessionRouter = router;`。kIsWeb 分支下 router 也照常创建（只是不注册）。
4. 文件末尾新增 getter（与 `echoLoopAudioHandler` 同款）：

```dart
MediaSessionRouter get echoLoopMediaSessionRouter {
  final router = _globalMediaSessionRouter;
  if (router == null) {
    throw StateError('MediaSessionRouter has not been initialized');
  }
  return router;
}
```

### 风险评估（已对 audio_service 0.18.18 源码核实）

- **初始值时序**：SwitchAudioHandler 自身 subject 未 seeded，但构造里 `inner = inner` 立即订阅 echo 的 seeded subject，初值下一个 microtask 到达，远早于平台通道往返；audio_service 内部对 playbackState 的同步读取带 hasValue 守卫或发生在运行期回调。无启动崩溃风险；router 测试中加「构造后补发初值」断言钉死该假设。
- **回调覆盖完整性**：CompositeAudioHandler 转发全部抽象方法，默认 inner=echo 时逐方法行为与今天直接注册完全一致——零回归的结构性保证。
- **已知语义（非风险）**：video 激活期间 echo 的广播进不了系统（预期）；页面进入时先暂停音频链路（见 2.8 礼让），不存在「音频在播却没锁屏控件」窗口。源码注释 `XXX: This only works in one direction` 指外部写 router.mediaItem 不回灌 inner——我们从不这么写。

## 2.4 MediaPlayerBackend 抽象与 media_kit 实现

### 新文件 `lib/services/media_player_backend.dart`（纯接口，零 media_kit import——测试可构造 Fake 的关键）

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';

/// 媒体播放后端抽象。真实实现是 media_kit（flutter test 中不可构造）；
/// 测试注入 FakeMediaPlayerBackend。位置/时长均为**绝对时间**
/// （media_kit 无 clip 概念，§7.15 天然满足）。
abstract class MediaPlayerBackend {
  Future<void> open(String filePath);          // 打开但不起播
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);        // 绝对位置
  Future<void> setRate(double rate);
  /// false → 断视频轨只出声（media_kit: setVideoTrack(VideoTrack.no())）；
  /// true → 恢复（VideoTrack.auto()）。进后台/回前台用。
  Future<void> setVideoTrackEnabled(bool enabled);
  Future<void> dispose();

  Duration get position;                       // 同步最近值
  Duration? get duration;                      // 未解析时 null
  bool get playing;
  double get rate;

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  /// 每次自然播完发一个事件（media_kit stream.completed 过滤 true）。
  Stream<void> get completedStream;

  Widget buildVideoView();                     // 渲染画面的 widget
}
```

### 新文件 `lib/services/media_kit_player_backend.dart`

```dart
class MediaKitPlayerBackend implements MediaPlayerBackend {
  MediaKitPlayerBackend() : _player = Player() {
    _controller = VideoController(_player);
  }
  final Player _player;
  late final VideoController _controller;
  // 同步 getter 读 _player.state.position/.duration/.playing/.rate；
  //   duration 为 Duration.zero 时返回 null（未解析）。
  // positionStream = _player.stream.position；durationStream = .duration；
  // playingStream = .playing；bufferingStream = .buffering；
  // completedStream = _player.stream.completed.where((c) => c)。
  // open: _player.open(Media(filePath), play: false)
  // setVideoTrackEnabled: enabled ? VideoTrack.auto() : VideoTrack.no()
  // buildVideoView: Video(controller: _controller, controls: NoVideoControls,
  //                       fit: BoxFit.contain)
  // dispose: _player.dispose()
}
```

### media_kit `completed` 的防御性假设（写进实现注释，对应真机验证项 R3）

1. 默认 `PlaylistMode.none` 下每次自然播完 `stream.completed` 恰发一次 `true`；若某平台重复发，§7.6 协程「一次 await 只解析一次事件」天然免疫。
2. **不依赖**播完后 `position`/`playing` 的取值：整篇循环回卷一律显式 `seek(Duration.zero)` 再 `play()`；播完后续播先判 `position >= duration - 300ms` 则回零。
3. 播完后直接 `play()` 可能不重启（部分平台）——上一条的显式 seek 同时消除该问题。

## 2.5 EchoLoopMediaHandler

### 新文件 `lib/services/echo_loop_media_handler.dart`

```dart
/// 视频链路的媒体会话 handler。不直接注册进 AudioService，经 MediaSessionRouter
/// 激活/交还。与 EchoLoopAudioHandler 并存、互不感知。
class EchoLoopMediaHandler extends BaseAudioHandler with SeekHandler {
  EchoLoopMediaHandler(this._backend) {
    // 订阅 backend 的 playing/buffering/duration/completed 流 → _broadcastState()。
    // 刻意不用 positionStream 触发广播：audio_service 客户端按
    // updatePosition+timestamp+speed 外推，离散事件时广播即可，避免通知栏刷屏；
    // seek/setSpeed 末尾显式广播一次（对齐 EchoLoopAudioHandler 做法）。
    // durationStream 首个非零值 → mediaItem.copyWith(duration:)（对齐 :24-38 模式）。
  }

  final MediaPlayerBackend _backend;
  MediaPlayerBackend get backend => _backend;   // engine 取裸流用（对齐 handler.player）

  Future<void> Function()? _onPlayCommand;      // 锁屏 play/pause 转业务回调，
  Future<void> Function()? _onPauseCommand;     // 语义照抄 EchoLoopAudioHandler :85-86
  void setTransportHandlers({Future<void> Function()? onPlay,
                             Future<void> Function()? onPause});

  /// 锁屏封面：复用 echo handler 已落盘的同一文件
  /// （getAppDataDirectory()/now_playing_artwork.png，启动时已写入；不存在则无封面）。
  /// 刻意小范围重复取路径逻辑，换取 EchoLoopAudioHandler 零改动；
  /// 未来删 just_audio 链路时合并成共享 helper。
  Future<void> prepareArtwork();

  /// 只订阅中断/becomingNoisy（session 的 configure 已由 echo handler 全局做过，
  /// 不重复）。守卫 `_backend.playing`——两个 handler 并存监听同一会话流，
  /// 各自只在自家 player 在播时响应，互不误伤。
  Future<void> configureInterruptions();

  void setNowPlaying({required String id, required String title, String? subtitle});
  // → mediaItem.add(MediaItem(id:, title:, artist: subtitle ?? 'Echo Loop',
  //                           artUri: _artworkUri))

  /// 直接驱动 backend（不经业务回调），供 MediaEngine 内部协程用——
  /// 对齐 playPlayer/pausePlayer 的分工（引擎内直驱、系统命令走回调，避免回环）。
  Future<void> playBackend() async { await _backend.play(); }
  Future<void> pauseBackend() async { await _backend.pause(); }

  @override Future<void> play();     // _onPlayCommand ?? playBackend（照抄 :328-335）
  @override Future<void> pause();    // _onPauseCommand ?? pauseBackend
  @override Future<void> stop();     // pauseBackend + _broadcastState；不广播 idle
                                     // （会话回收统一走 router.deactivate）
  @override Future<void> seek(Duration position);  // backend.seek + _broadcastState
  @override Future<void> setSpeed(double speed);   // backend.setRate + _broadcastState

  Future<void> dispose();            // 取消全部订阅（不 dispose backend——归 engine）

  void _broadcastState() {
    playbackState.add(PlaybackState(
      controls: [_backend.playing ? MediaControl.pause : MediaControl.play,
                 MediaControl.stop],
      systemActions: {MediaAction.play, MediaAction.pause,
                      MediaAction.seek, MediaAction.stop},
      androidCompactActionIndices: const [0, 1],
      processingState: _mapState(),
      playing: _backend.playing,
      updatePosition: _backend.position,   // 天然绝对（无 clip），§7.15 平凡满足
      bufferedPosition: _backend.position,
      speed: _backend.playing ? _backend.rate : 0.0,
    ));
  }

  AudioProcessingState _mapState() {
    if (!_opened) return AudioProcessingState.idle;
    if (_buffering) return AudioProcessingState.buffering;
    return AudioProcessingState.ready;   // completed 也报 ready（§7.7：对系统从不
                                         // 「结束」，防 iOS 钉死进度条）
  }
}
```

与 echo handler 的刻意差异：① 无 clip 机制 → 没有 `_clipStart/_clipActive/_fullDuration` 补偿字段；② 无 `_logicalPlaying/_progressFrozen`（视频页无停顿倒计时假播放需求，本阶段不实现）。

## 2.6 MediaEngine

### 新文件 `lib/models/media_engine_state.dart`

```dart
/// 不复用 AudioEngineState：那里的 clipStart/isClipActive 是 just_audio clip
/// 补偿语义，media_kit 链路位置天然绝对，带上只会误导。
class MediaEngineState {
  final int sessionId;            // 默认 0
  final bool isLoading;
  final String? errorMessage;     // 技术信息；页面层映射 l10n 文案
  final String? currentMediaId;
  final Duration? totalDuration;
  final bool videoTrackEnabled;   // 默认 true（后台断轨状态记录）
  const MediaEngineState({...});
  MediaEngineState copyWith({...});
}
```

### 新文件 `lib/providers/media_engine/media_engine_provider.dart`（+ `.g.dart`，riverpod_generator）

```dart
/// 测试缝：真实工厂造 MediaKitPlayerBackend（flutter test 不可构造），
/// 测试 override 本 provider 注入 Fake。
@Riverpod(keepAlive: true)
MediaPlayerBackend Function() mediaBackendFactory(Ref ref) =>
    () => MediaKitPlayerBackend();

/// 测试缝：默认读全局 router（未 init 时抛 StateError）；测试 override 成
/// MediaSessionRouter(defaultHandler: BaseAudioHandler())——纯 Dart 可构造。
@Riverpod(keepAlive: true)
MediaSessionRouter mediaSessionRouter(Ref ref) => echoLoopMediaSessionRouter;

@Riverpod(keepAlive: true)
class MediaEngine extends _$MediaEngine {
  MediaPlayerBackend? _backend;
  EchoLoopMediaHandler? _handler;

  @override
  MediaEngineState build() => const MediaEngineState();

  // --- 链路生命周期（决策 C） ---
  Future<void> ensureChain();     // 幂等；factory 造 backend → EchoLoopMediaHandler(backend)
                                  // → handler.prepareArtwork() + configureInterruptions()
  Future<void> disposeChain() async {
    final handler = _handler; final backend = _backend;
    _handler = null; _backend = null;
    if (handler != null) {
      ref.read(mediaSessionRouterProvider).deactivate(handler); // ① 先交还会话
      await handler.dispose();                                  // ② 再断订阅
    }
    await backend?.dispose();                                   // ③ 最后杀 mpv
    // sessionId 单调不回退：旧协程持有的 id 永不复活
    state = MediaEngineState(sessionId: state.sessionId + 1);
  }

  // --- 加载 ---
  Future<Duration?> loadMedia(AudioItem item, double speed) async {
    await ensureChain();
    state = state.copyWith(isLoading: true, errorMessage: null);
    final path = await item.getFullAudioPath();          // 异步！（audio_item.dart:229）
    if (path == null) {
      state = state.copyWith(isLoading: false, errorMessage: 'file not available');
      return null;
    }
    try {
      _handler!.setNowPlaying(id: item.id, title: item.name);
      await _backend!.open(path);
      await _backend!.setRate(speed);
      ref.read(mediaSessionRouterProvider).activate(_handler!);  // 加载成功才抢会话
      final duration = _backend!.duration ??
          await _backend!.durationStream
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 10));
      state = state.copyWith(totalDuration: duration,
          currentMediaId: item.id, isLoading: false);
      return duration;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  // --- Session 管理（逐字对齐 AudioEngine :449-459） ---
  int newSession();                       // sessionId++ 并返回
  bool isActiveSession(int id);
  int get currentSessionId;

  // --- 基础控制（对齐 AudioEngine 语义） ---
  Future<void> play();                    // handler.playBackend()
  Future<void> pause();                   // sessionId++ 再 pauseBackend（:192 语义）
  Future<void> pauseKeepSession();        // 只 pauseBackend（:203 语义）
  Future<void> stop();                    // sessionId++ 再 handler.stop()
  Future<void> seek(Duration pos);        // handler.seek（绝对位置）
  Future<void> setSpeed(double speed);
  Future<void> setVideoTrackEnabled(bool enabled);  // backend 转发 + state 记录

  // --- 只读 ---
  bool get isPlaying;                     Duration get currentPosition;
  Duration? get totalDuration;            // state.totalDuration
  Stream<Duration> get positionStream;    // _backend?.positionStream ?? Stream.empty()
  Stream<bool> get playingStream;
  Widget buildVideoView();                // _backend!.buildVideoView()
  void setTransportHandlers({onPlay, onPause});   // 转发 handler

  // --- 播放基元（见 2.7） ---
  Future<void> playRangeOnce(Duration start, Duration end, int sessionId);
  Future<void> playToEnd(int sessionId);
}
```

## 2.7 播放基元（sessionId 守卫；media_kit 无 clip → 终点自检）

```dart
Future<void> playRangeOnce(Duration start, Duration end, int sessionId) async {
  final handler = _handler; final backend = _backend;
  if (handler == null || backend == null || !isActiveSession(sessionId)) return;

  await handler.seek(start);                       // ① 绝对 seek（无 setClip）
  if (!isActiveSession(sessionId)) return;         //   每个 await 后重查（§7.6 范式）

  final reached = _awaitRangeEndOrInvalid(backend, end, sessionId); // ② 先订阅
  await handler.playBackend();                     // ③ 后起播（防竞态漏事件）
  if (!isActiveSession(sessionId)) { await handler.pauseBackend(); return; }

  await reached;                                   // ④ 终点/completed/session 失效
  if (isActiveSession(sessionId)) {
    await handler.pauseBackend();                  // ⑤ 到点暂停（session 保留，供循环续用）
  }
}

/// 区间终点等待器。三路收敛，谁先到谁完成（完成即取消全部监听，幂等）：
///  a) positionStream 报 pos >= end；
///  b) completedStream（区间尾 == 文件尾时 position 可能到不了 end）；
///  c) 200ms 守卫 Timer——position 流在暂停/卡顿时停发，session 失效必须
///     不依赖位置事件也能退出（关键防泄漏点）；同时兜底位置流粒度。
Future<void> _awaitRangeEndOrInvalid(
    MediaPlayerBackend backend, Duration end, int sessionId) {
  final completer = Completer<void>();
  StreamSubscription? posSub, doneSub; Timer? guard;
  void finish() {
    if (completer.isCompleted) return;
    posSub?.cancel(); doneSub?.cancel(); guard?.cancel();
    completer.complete();
  }
  posSub = backend.positionStream.listen((pos) {
    if (pos >= end || !isActiveSession(sessionId)) finish();
  });
  doneSub = backend.completedStream.listen((_) => finish());
  guard = Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (!isActiveSession(sessionId) || backend.position >= end) finish();
  });
  return completer.future;
}

Future<void> playToEnd(int sessionId) async {
  final handler = _handler; final backend = _backend;
  if (handler == null || backend == null || !isActiveSession(sessionId)) return;

  final done = _awaitCompletedOrInvalid(backend, sessionId);
  // 同款等待器：completedStream 一次事件解析一次 await（§7.6）+ 200ms session 守卫
  await handler.playBackend();
  if (!isActiveSession(sessionId)) { await handler.pauseBackend(); }
  await done;
}
```

终点过冲 ≤ 位置流粒度 + pause 延迟（预计 <200ms），测试页可接受，写进实现注释。

## 2.8 页面实现（`lib/screens/video_playback_test_screen.dart` 全量替换内部实现）

### 状态字段

```dart
bool _initializing = true;  String? _initError;
List<Sentence> _sentences = const [];       // build 里 watch 后同步进字段供回调用
int _playingSentenceIndex = -1;
bool _isPlaying = false;
bool _hideVideo = false;                    // 隐藏画面（Offstage）
int _sentenceLoopCount = 1;                 // 区间循环：1 / 3 / 0(∞)
bool _loopWhole = false;                    // 整篇循环开关
int _gen = 0;                               // 页面协程代际
StreamSubscription<Duration>? _posSub;  StreamSubscription<bool>? _playingSub;
AppLifecycleListener? _lifecycle;
```

### 初始化（initState → `unawaited(_init())`；`AppLifecycleListener(onStateChange: _onLifecycle)`，先例 study_task_controller_mixin.dart:77）

```dart
Future<void> _init() async {
  try {
    // 礼让：抢媒体会话前先停现有音频链路（只调公开方法，零侵入）
    final audio = ref.read(audioEngineProvider.notifier);
    if (audio.isPlaying) await audio.pause();

    final engine = ref.read(mediaEngineProvider.notifier);
    final duration = await engine.loadMedia(widget.audioItem, 1.0);
    if (!mounted) return;
    if (duration == null) {                  // loadMedia 内部已吞异常并写 errorMessage
      setState(() { _initError = ref.read(mediaEngineProvider).errorMessage;
                    _initializing = false; });
      return;
    }
    engine.setTransportHandlers(onPlay: _playWhole, onPause: _pause);  // 锁屏回调
    _posSub = engine.positionStream.listen(_onPosition);
    _playingSub = engine.playingStream.listen(
        (p) { if (mounted && p != _isPlaying) setState(() => _isPlaying = p); });
    setState(() => _initializing = false);
  } catch (e) {
    if (mounted) setState(() { _initError = '$e'; _initializing = false; });
  }
}

/// 高亮：直接订阅位置流，索引变了才 setState（二分 O(logN)，无需节流 Timer；
/// media_kit 位置流粒度 ~100ms 级）。
void _onPosition(Duration pos) {
  final idx = SentenceTracker.findSentenceIndexByPosition(_sentences, pos);
  if (idx != _playingSentenceIndex && mounted) {
    setState(() => _playingSentenceIndex = idx);
  }
}
```

### 循环协程（页面层，照抄 §7.6 模式：gen + sessionId 双守卫）

```dart
Future<void> _playSentence(Sentence s) async {           // 点句 / 区间循环
  final engine = ref.read(mediaEngineProvider.notifier);
  final gen = ++_gen;                                    // 作废上一个页面协程
  final sid = engine.newSession();                       // 作废引擎侧旧 session
  var played = 0;
  while (mounted && gen == _gen && engine.isActiveSession(sid)) {
    await engine.playRangeOnce(s.startTime, s.endTime, sid);
    if (!mounted || gen != _gen || !engine.isActiveSession(sid)) return;
    played += 1;
    if (_sentenceLoopCount != 0 && played >= _sentenceLoopCount) return;
  }                                                      // playRangeOnce 已到点暂停
}

Future<void> _playWhole() async {                        // 播放按钮 / 锁屏 play
  final engine = ref.read(mediaEngineProvider.notifier);
  final gen = ++_gen;
  final sid = engine.newSession();
  final total = engine.totalDuration;                    // 防御性假设 2/3：播完态续播
  if (total != null &&
      engine.currentPosition >= total - const Duration(milliseconds: 300)) {
    await engine.seek(Duration.zero);
    if (!mounted || gen != _gen || !engine.isActiveSession(sid)) return;
  }
  while (mounted && gen == _gen && engine.isActiveSession(sid)) {
    await engine.playToEnd(sid);                         // 一次自然结束解析一次 await
    if (!mounted || gen != _gen || !engine.isActiveSession(sid)) return;
    if (!_loopWhole) { await engine.pauseKeepSession(); return; }  // 播完暂停保会话
    await engine.seek(Duration.zero);                    // 回卷显式 seek（假设 2）
    if (!mounted || gen != _gen || !engine.isActiveSession(sid)) return;
  }
}

Future<void> _pause() async {
  _gen++;                                                // 作废页面协程
  await ref.read(mediaEngineProvider.notifier).pause();  // sessionId++ + 暂停
}
```

播放按钮：`_isPlaying ? _pause() : _playWhole()`。循环开关只 setState 翻字段，**不打断在播协程**——`_playWhole` 每遍结束读最新 `_loopWhole`，与听力练习 settings 热读一致。

### 隐藏画面：Offstage（本阶段选它，不用 setVideoTrack）

```dart
Offstage(offstage: _hideVideo,
    child: SizedBox(height: 220, child: engine.buildVideoView())),
```

理由：Offstage 保持 `Video` widget 挂载、纹理不重绑，开关瞬时零中断；`setVideoTrack(no/auto)` 真正断开解码轨，恢复可能黑帧/track 重选延迟，且它已被生命周期逻辑占用（后台断轨）——两个开关共用一个机制会互相踩（回前台恢复轨会顶掉用户的「隐藏画面」选择）。Offstage 代价（隐藏时解码继续）对测试页可接受；未来正式页可做「隐藏画面 = Offstage + 断轨」合并优化。

### 生命周期

```dart
void _onLifecycle(AppLifecycleState s) {
  final engine = ref.read(mediaEngineProvider.notifier);
  switch (s) {
    case AppLifecycleState.paused:
    case AppLifecycleState.hidden:      // iOS hidden 先于 paused，幂等即可
      unawaited(engine.setVideoTrackEnabled(false));   // 断视频轨保音频（iOS 后台坑）
    case AppLifecycleState.resumed:
      unawaited(engine.setVideoTrackEnabled(true));
    default: break;
  }
}
```

iOS/Android 统一执行（Android 断轨同样省电、无副作用；若真机验证 R2 出问题再收窄成 `Platform.isIOS`）。

```dart
@override
void dispose() {
  _gen++;
  _lifecycle?.dispose();
  _posSub?.cancel(); _playingSub?.cancel();
  final engine = ref.read(mediaEngineProvider.notifier);
  engine.setTransportHandlers(onPlay: null, onPause: null);
  unawaited(engine.stop().then((_) => engine.disposeChain()));
  // disposeChain 内部顺序：router.deactivate（echo 状态补发刷新锁屏）
  // → handler 断订阅 → backend.dispose（杀 mpv）
  super.dispose();
}
```

### UI 结构与句子列表

`Scaffold(appBar: AppBar(title: Text(widget.audioItem.name)))`，body：错误态（`_initError` 非空：图标 + `videoLoadFailed` 文案 + 重试按钮重跑 `_init`）/ loading（`_initializing`）/ 正常态 Column：视频区（Offstage 包裹）→ 控制条（播放/暂停 IconButton、隐藏画面 Switch、整篇循环 Switch、区间循环 `SegmentedButton<int>`(1/3/0=∞)）→ `Expanded` 句子列表：

```dart
ParagraphSentenceListCard(
  sentences: _sentences,
  displayMode: RetellDisplayMode.showAll,
  keywordMap: const {},
  playingSentenceIndex: _playingSentenceIndex,
  autoFocusEnabled: true,
  onSentencePlayFrom: _playSentence,     // 编号区点击 → 区间播放
  onSentenceTap: null,                   // 测试页不进讲解页
)
```

`_sentences` 来自 build 中 `ref.watch(audioSentencesProvider(widget.audioItem.id))`（AsyncValue；data 时同步进字段）；空列表显示 `videoNoTranscript` 空态、隐藏列表但播放功能照常。

### l10n 新增（app_en.arb / app_zh.arb 成对，`videoTestPlaceholder` 附近）

`videoHideTrack`（隐藏画面/Hide video）、`videoLoopWhole`（整篇循环/Loop all）、`videoLoopSentence`（单句循环/Sentence loop）、`videoLoadFailed`（视频加载失败/Failed to load video）、`videoNoTranscript`（无字幕/No transcript）、`videoRetry`（重试/Retry）。

## 2.9 测试设计

新增共享 Fake：`test/helpers/shared/fake_media_player_backend.dart`——实现 `MediaPlayerBackend`，暴露 `emitPosition(Duration)`、`emitCompleted()`、`setDuration(Duration)`、playing 手动翻转、`openCalls/seekCalls/playCalls/pauseCalls/videoTrackCalls` 调用记录、可注入 `openError`；`buildVideoView` 返回 `SizedBox(key: Key('fake-video-view'))`。

| 测试文件（新建） | 覆盖 |
|---|---|
| `test/services/media_session_router_test.dart` | ① 构造后 playbackState/mediaItem 补发 defaultHandler 初值（钉死 2.3 时序假设）；② activate 后新 inner 广播进 router 流、旧 inner 不再进；③ 切回时立即重发 echo 当前值；④ play/pause/stop/seek 转发到当前 inner（两个录调用的 BaseAudioHandler 子类）；⑤ deactivate 守卫：非当前占用者 no-op；⑥ activate/deactivate 幂等。 |
| `test/services/echo_loop_media_handler_test.dart` | 注入 Fake backend：① playing/buffering 事件 → playbackState 映射（controls 随 playing 翻转）；② completed → processingState 仍为 ready（§7.7 回归点）；③ updatePosition = backend.position（绝对）；④ 暂停时 speed=0；⑤ transport 回调注册后 play/pause 走回调、清空后回退直驱；⑥ seek/setSpeed 转发 + 显式广播；⑦ durationStream 首值写进 mediaItem.duration。 |
| `test/providers/media_engine/media_engine_provider_test.dart` | override `mediaBackendFactoryProvider` + `mediaSessionRouterProvider`：① loadMedia 成功（open/setRate 调用、router.activate、totalDuration 落 state）；② 路径 null / open 抛异常 → errorMessage、**不** activate；③ pause() sessionId++、pauseKeepSession() 不变；④ playRangeOnce：seek→play 顺序、emitPosition 越过 end → 自动 pause、各守卫点 session 失效提前返回且主动 pause；⑤ 区间尾==文件尾时 emitCompleted 也能收敛；⑥ playToEnd：emitCompleted 前 await 不解析、session 失效经 200ms 守卫退出（fakeAsync）；⑦ disposeChain：deactivate 先于 backend.dispose、sessionId 递增不回卷、二次调用幂等。 |
| `test/screens/video_playback_test_screen_test.dart` | 同上 override + 内存 DAO 喂字幕：① loading→正常态、loadMedia 失败→错误态+重试；② 播放/暂停按钮驱动 fake playing 翻转图标；③ 点句 A 再立刻点句 B：只有 B 的 seek/play 生效（gen+session 竞态回归点）；④ 区间循环 ∞：越过 end 自动回 seek(start) 重播、切 1 次后播 1 遍即停；⑤ 手动暂停后 emitPosition 越过旧 end 不再误 pause；⑥ 高亮随 emitPosition 变化；⑦ 隐藏画面：`Offstage.offstage == true` 且 fake-video-view 仍在树中（findsOneWidget）；⑧ `tester.binding.handleAppLifecycleStateChanged(paused/resumed)` → videoTrackCalls 记录 false/true；⑨ dispose 页面 → backend.disposeCalled、router 回落 default。 |
| 回归清单（零改动纯复用，跑绿即证明） | `test/services/background_audio_handler_test.dart`（注意：若直接测 `initEchoLoopAudioHandler`，确认 router 包装后仍绿——函数返回值/全局 getter 语义未变）、`test/providers/audio_engine_provider_test.dart`、`test/providers/audio_engine/foreground_audio_engine_provider_test.dart`、`test/providers/listening_practice/` 全部、`test/router/` 全部。 |

收尾：`dart run build_runner build`（新 riverpod provider）→ `flutter analyze` + `flutter test` 全量 + `dart format .`。

## 2.10 风险清单（真机验证项，不阻塞实现）

- **R1（最高）iOS 后台音频**：media_kit（mpv/audiounit）锁屏后能否持续出声、AVAudioSession 是否保持激活（speech() 理论够用）。失败 fallback：进后台时额外调 echo handler 公开的 `startKeepAlive()` 静音保活（公开方法，零改动可用）。
- **R2 断轨/恢复观感**：`setVideoTrack(no→auto)` 回前台是否黑帧/卡顿；Android 有问题则收窄成 iOS-only。
- **R3 completed 行为**：验证 2.4 三条防御性假设在 iOS+Android 真机的实际表现。
- **R4 锁屏切换观感**：router activate/deactivate 时锁屏卡片是否平滑替换（BehaviorSubject 补发应为瞬时）。
- **R5 会话共存**：视频页 mpv 出声期间 just_audio 空闲无双声；退出视频页后音频链路功能完好（Free Player 全流程回归）。
- **R6 media_kit 锁版本**：Limited Maintenance，pubspec 精确 pin；升级需重跑本清单。
- **R7 包体积**：media_kit_libs_video 每平台增加约 15-30MB，release 合入前 `flutter build --analyze-size` 实测评估。

## 2.11 输入/输出边界

- **输入**：阶段一契约（构造签名、路由两变体、`audioSentencesProvider`）。
- **输出**：可交互视频测试页 + 可复用的 media_kit 链路四件套（router / handler / backend / engine），为未来统一链路与 Windows 打底。
- **不产出**：不写 DB、不接 `listeningPracticeProvider`、不删 just_audio 任何代码、不做 Windows 媒体会话。
- **对现有文件的全部改动（穷举）**：`pubspec.yaml`（3 个锁版本依赖）、`main.dart`（1 行 MediaKit.ensureInitialized）、`background_audio_handler.dart`（仅文件底部 init 函数包 router + 新全局 getter，类本体零改动）、`video_playback_test_screen.dart`（内部实现替换）、两个 arb（6 个 key）。其余全部为新文件：`lib/services/media_session_router.dart`、`lib/services/media_player_backend.dart`、`lib/services/media_kit_player_backend.dart`、`lib/services/echo_loop_media_handler.dart`、`lib/models/media_engine_state.dart`、`lib/providers/media_engine/media_engine_provider.dart`（+.g.dart）。

---

## 手动验证（阶段二完成后，真机）

1. 导入 mp4（带同名 srt）→ 学习计划页 → 「随心听」进视频测试页：画面渲染、不自动播放。
2. 播放/暂停 → 隐藏画面（画面消失声音继续、再开无中断）→ 点句只播该句 → 区间循环切 3 次/∞ → 整篇循环开关 → 高亮跟随。
3. 切后台/锁屏：音频继续、锁屏出现视频标题的播放控件，锁屏 play/pause/seek 可用；回前台画面恢复、位置连续。
4. 退出视频页 → 回音频条目跑 Free Player 全流程：锁屏控件归属正确、零回归（R5）。
5. Android 重点验证前台服务与通知栏；iOS 重点验证 R1（后台持续出声）与 R2（断轨恢复观感）。

## 收尾（每阶段完成后按 CLAUDE.md 收尾流程）

更新 TASKS.md（勾选+完成时间）与 PLAN.md（如里程碑变化）；`dart format .`；输出完成摘要。
