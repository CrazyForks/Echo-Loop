/// 跟读会话控制器
///
/// 组合 [RepeatFlowEngine] 驱动跟读流程，添加跟读页面专属逻辑：
/// - 初始化（读书签/断点/设置）
/// - 学习计时（StudyTaskControllerMixin）
/// - 书签管理、断点保存、进度统计
///
/// Screen 只读 state、只调公开方法，不直接操作资源服务。
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../analytics/analytics_providers.dart';
import '../../analytics/audio_event_params.dart';
import '../../analytics/models/event_names.dart';
import '../../features/usage/usage_event.dart';
import '../../features/usage/usage_providers.dart';
import '../../database/enums.dart' show LearningStage;
import '../../database/providers.dart';
import '../../models/intensive_listen_settings.dart';
import '../../models/audio_item.dart';
import '../../models/media_load_result.dart';
import '../../models/sense_group_range_playback.dart';
import '../../models/sentence.dart';
import '../../models/study_stage.dart';
import '../../services/app_logger.dart';
import '../audio_engine/audio_engine_provider.dart';
import '../audio_engine/foreground_audio_engine_provider.dart';
import '../learning_progress_provider.dart';
import '../learning_session/sentence_playback_engine.dart';
import '../learning_session/intensive_listen_playback_driver.dart';
import '../media_engine/media_engine_provider.dart';
import '../media_engine/media_sense_group_range_playback.dart';
import '../repeat_flow/repeat_flow_engine.dart';
import '../repeat_flow/repeat_flow_phase.dart';
import '../speech/speech_recording_controller.dart';
import '../listening_practice/bookmark_manager.dart';
import '../intensive_listen_prefs_provider.dart';
import '../../models/stage_settings_overrides.dart';
import '../study_task_controller_mixin.dart';
import 'listen_and_repeat_session_state.dart';
import 'listen_and_repeat_settings_provider.dart';

part 'listen_and_repeat_controller.g.dart';

/// 跟读会话控制器
@Riverpod(keepAlive: true)
class ListenAndRepeatController extends _$ListenAndRepeatController
    with StudyTaskControllerMixin {
  /// 跟读流程引擎
  late final RepeatFlowEngine _engine;

  /// 当前会话的句子播放驱动；音频与视频共用同一流程状态机。
  late SentencePlaybackDriver _playback;

  /// 是否为自由练习模式
  bool _isFreePlay = false;

  /// 当前会话句子列表（包含页面级业务字段，如 bookmark 状态）
  List<Sentence> _sentences = [];
  bool _usesMediaEngine = false;
  int _mediaEntryGeneration = 0;
  bool _mediaSessionReady = false;
  bool _sessionPrepared = false;
  MediaEngine? _ownedMediaEngine;
  int? _ownedMediaGeneration;
  SenseGroupRangePlayback? _senseGroupRangePlayback;

  @override
  ListenAndRepeatSessionState build() {
    _playback = ForegroundSentencePlaybackDriver(
      ref.read(foregroundAudioEngineProvider.notifier),
    );
    // 创建引擎
    _engine = RepeatFlowEngine(
      onStateChanged: _onEngineStateChanged,
      callbacks: RepeatFlowCallbacks(
        // 运行时读取当前驱动：媒体初始化会替换 [_playback]，不能捕获旧音频实例。
        pauseAudio: () => unawaited(_playback.pause()),
        playSentence: _playSentence,
        startRecording: _startRecording,
        cancelRecording: _cancelRecording,
        stopAndEvaluate: _stopAndEvaluate,
        clearRecording: _clearRecording,
        setMaxRecordingDuration: _setMaxRecordingDuration,
        hasDetectedSpeech: _hasDetectedSpeech,
      ),
      logTag: 'L&R',
    );

    // 监听录音控制器状态变化 → 桥接到 engine
    ref.listen(speechRecordingControllerProvider, _onRecordingStateChanged);

    // 打印状态变化日志
    listenSelf((prev, next) {
      if (prev?.phase.runtimeType != next.phase.runtimeType ||
          prev?.sentenceIndex != next.sentenceIndex ||
          prev?.repeatIndex != next.repeatIndex) {
        final recPhase = ref.read(speechRecordingControllerProvider).phase;
        AppLogger.log(
          'L&R State',
          '${next.phase.runtimeType} | '
              '句${next.sentenceIndex + 1}/${next.totalSentences} '
              '遍${next.repeatIndex + 1}/${next.totalRepeats} | '
              '录音=$recPhase | '
              'token=${next.flowToken}',
        );
      }
    });

    ref.onDispose(() {
      _playback.unbindLockScreen();
      _engine.dispose();
      final mediaEngine = _ownedMediaEngine;
      if (mediaEngine != null) unawaited(mediaEngine.releaseFromScreen());
    });
    return const ListenAndRepeatSessionState();
  }

  // ========== 初始化 ==========

  /// 初始化跟读任务（从 DB 读数据 + 启动学习计时 + 准备会话）
  ///
  /// [smartSpeed] 按当前难度/阶段算出的动态默认速度;用户未在偏好里设过速度时用它。
  /// 句间停顿/遍数等其余设置由按槽位偏好 [intensiveListenPrefsProvider] resolve 出。
  Future<void> initialize({
    required String audioItemId,
    required List<Sentence> allSentences,
    required bool isFreePlay,
    double smartSpeed = 1.0,
    LearningStage? stage,
    SentencePlaybackDriver? playbackDriver,
    bool usesMediaEngine = false,
  }) async {
    _sessionPrepared = false;
    _isFreePlay = isFreePlay;
    _usesMediaEngine = usesMediaEngine;
    if (!usesMediaEngine) _senseGroupRangePlayback = null;
    _playback =
        playbackDriver ??
        ForegroundSentencePlaybackDriver(
          ref.read(foregroundAudioEngineProvider.notifier),
        );

    // 录音类任务用前台引擎播放原句、不上锁屏。进任务停掉媒体引擎，清除上一个媒体任务
    // （精听/盲听/Free Player）残留的锁屏/通知栏卡片（非idle→idle → stopService）。
    await ref.read(audioEngineProvider.notifier).stop();

    // 从 DB 读难句索引
    final bookmarkDao = ref.read(bookmarkDaoProvider);
    final bookmarkedIndices = await bookmarkDao.getBookmarkedIndices(
      audioItemId,
    );
    // 难句列表来自数据库索引，而 [allSentences] 只承载字幕正文；进入跟读会话前
    // 必须同步收藏态，否则首句会被误判为“未收藏”，点击后还会走新增分支。
    final sessionSentences = BookmarkManager.createSentenceBookmarkSnapshot(
      allSentences,
      bookmarkedIndices,
    );
    final difficultSentences = sessionSentences
        .where((s) => bookmarkedIndices.contains(s.index))
        .toList();

    // 从 DB 读断点
    final progress = await ref
        .read(learningProgressNotifierProvider.notifier)
        .getLatestOrEnsureProgress(audioItemId);
    int startIndex = 0;
    if (isFreePlay) {
      startIndex = progress.freePlayShadowingSentenceIndex ?? 0;
    } else {
      startIndex = progress.shadowingSentenceIndex ?? 0;
    }

    // 根据难度计算目标遍数(动态默认遍数)
    final targetPlayCount = targetPlayCountForDifficulty(
      progress.difficulty.value,
    );

    // 难句跟读仅在首学,槽位固定;自由练习与按计划共用同一份偏好记忆。
    final slot = stageSlotKey(
      StageSettingsSlots.listenAndRepeat,
      stage ?? LearningStage.firstLearn,
    );
    final settings = ref
        .read(intensiveListenPrefsProvider.notifier)
        .resolve(
          slot,
          smartSpeed: smartSpeed,
          smartRepeatCount: targetPlayCount,
        );

    // 初始化设置(完整设置 = 偏好叠加智能默认/动态遍数)
    ref
        .read(listenAndRepeatSettingsProvider.notifier)
        .initialize(settings, slot);

    // 学习任务通用初始化（计时、LP、音频、analytics、recorder 注入）
    await initStudyTask(
      ref,
      audioItemId: audioItemId,
      stage: StudyStage.listenAndRepeat,
      isFreePlay: isFreePlay,
      manageForegroundAudioEngine: !usesMediaEngine,
    );

    // 构造 config 并准备会话
    final config = RepeatFlowConfig(
      audioItemId: audioItemId,
      promptIdPrefix: 'lar',
      getRepeatCount: (_) =>
          ref.read(listenAndRepeatSettingsProvider).repeatCount,
      getIntervalDuration: (s) {
        final st = ref.read(listenAndRepeatSettingsProvider);
        return switch (st.pauseMode) {
          PauseMode.smart => Duration(
            milliseconds: (1000 + (s.duration.inMilliseconds * 0.6).round())
                .clamp(kSmartPauseMinMs, kSmartPauseMaxMs),
          ),
          PauseMode.fixed => Duration(seconds: st.fixedPauseSeconds),
          PauseMode.multiplier => Duration(
            milliseconds: math.max(
              (s.duration.inMilliseconds * st.pauseMultiplier).round(),
              kMultiplierPauseMinMs,
            ),
          ),
        };
      },
      isManualMode: () =>
          ref.read(listenAndRepeatSettingsProvider).isManualMode,
    );

    await prepareSession(
      sentences: difficultSentences,
      config: config,
      startIndex: startIndex,
      isFreePlay: isFreePlay,
    );
    _playback.bindLockScreen(
      onPlay: replayCurrentSentence,
      onPause: () async => enterWaitingForUser(),
      onNext: nextSentence,
      onPrevious: previousSentence,
    );
    ref.read(analyticsServiceProvider).track(Events.listenRepeatStart, {
      ...ref.audioEventParams(audioItemId),
      EventParams.totalSentences: difficultSentences.length,
    });
  }

  /// 使用逐句精听同一 MediaEngine 初始化视频难句跟读。
  Future<MediaLoadResult> initializeMedia({
    required AudioItem mediaItem,
    required List<Sentence> allSentences,
    required bool isFreePlay,
    double smartSpeed = 1.0,
    LearningStage? stage,
  }) async {
    final generation = ++_mediaEntryGeneration;
    bool isCurrent() => generation == _mediaEntryGeneration;
    AppLogger.log(
      'L&R MediaEntry',
      '开始加载: mediaId=${mediaItem.id}, generation=$generation',
    );

    await ref.read(audioEngineProvider.notifier).stop();
    if (!isCurrent()) return MediaLoadResult.cancelled;

    final settingsSlot = stageSlotKey(
      StageSettingsSlots.listenAndRepeat,
      stage ?? LearningStage.firstLearn,
    );
    final settings = ref
        .read(intensiveListenPrefsProvider.notifier)
        .resolve(settingsSlot, smartSpeed: smartSpeed);
    final mediaEngine = ref.read(mediaEngineProvider.notifier);
    _ownedMediaEngine = mediaEngine;
    _ownedMediaGeneration = generation;
    final duration = await mediaEngine.loadMedia(
      mediaItem,
      settings.playbackSpeed,
    );
    if (!isCurrent()) {
      AppLogger.log(
        'L&R MediaEntry',
        '加载结果已过期，释放媒体: mediaId=${mediaItem.id}, generation=$generation',
      );
      await _releaseOwnedMediaEngine(mediaEngine, generation);
      return MediaLoadResult.cancelled;
    }
    if (duration == null) {
      AppLogger.log(
        'L&R MediaEntry',
        '加载失败，释放媒体: mediaId=${mediaItem.id}, generation=$generation',
      );
      await _releaseOwnedMediaEngine(mediaEngine, generation);
      return MediaLoadResult.failure;
    }

    // 与逐句精听的呈现规则一致：视频字幕轨默认关闭，用户点 CC 后再按需加载。
    await mediaEngine.setSubtitleTrackData(null);
    if (!isCurrent()) {
      AppLogger.log(
        'L&R MediaEntry',
        '字幕初始化后任务已取消: mediaId=${mediaItem.id}, generation=$generation',
      );
      await _releaseOwnedMediaEngine(mediaEngine, generation);
      return MediaLoadResult.cancelled;
    }

    _senseGroupRangePlayback = MediaSenseGroupRangePlayback(
      engine: mediaEngine,
      playbackSpeed: () =>
          ref.read(listenAndRepeatSettingsProvider).playbackSpeed,
    );
    await initialize(
      audioItemId: mediaItem.id,
      allSentences: allSentences,
      isFreePlay: isFreePlay,
      smartSpeed: smartSpeed,
      stage: stage,
      playbackDriver: MediaSentencePlaybackDriver(mediaEngine),
      usesMediaEngine: true,
    );
    if (!isCurrent()) {
      AppLogger.log(
        'L&R MediaEntry',
        '业务初始化后任务已取消: mediaId=${mediaItem.id}, generation=$generation',
      );
      await exitLearningMode();
      return MediaLoadResult.cancelled;
    }
    _mediaSessionReady = true;
    AppLogger.log(
      'L&R MediaEntry',
      '加载完成: mediaId=${mediaItem.id}, generation=$generation',
    );
    return MediaLoadResult.ready;
  }

  /// 取消正在进入的视频跟读；迟到结果由 generation guard 丢弃。
  Future<void> cancelMediaEntry() async {
    final generation = ++_mediaEntryGeneration;
    AppLogger.log(
      'L&R MediaEntry',
      '取消进入: generation=$generation, ready=$_mediaSessionReady',
    );
    if (_mediaSessionReady) {
      await exitLearningMode();
    } else {
      final mediaEngine = _ownedMediaEngine;
      final mediaGeneration = _ownedMediaGeneration;
      if (mediaEngine != null && mediaGeneration != null) {
        await _releaseOwnedMediaEngine(mediaEngine, mediaGeneration);
      }
    }
  }

  // ========== 公开方法（Screen 调用） ==========

  /// 准备会话数据
  Future<void> prepareSession({
    required List<Sentence> sentences,
    required RepeatFlowConfig config,
    int startIndex = 0,
    bool isFreePlay = false,
  }) async {
    _isFreePlay = isFreePlay;
    _sentences = sentences.map((s) => s.copyWith()).toList();
    _engine.prepare(
      sentences: _sentences,
      config: config,
      startIndex: startIndex,
    );
    _sessionPrepared = true;

    // 同步录音控制器模式
    ref
        .read(speechRecordingControllerProvider.notifier)
        .setManualMode(config.isManualMode());
  }

  /// 开始播放
  Future<void> startPlaying() async => _engine.startPlaying();

  /// 将速度应用到当前实际播放驱动，音频仍委托原前台引擎。
  Future<void> applyPlaybackSpeed(double speed) => _playback.setSpeed(speed);

  /// 进入等待用户操作状态
  void enterWaitingForUser() => _engine.enterWaitingForUser();

  /// 当前原句播完后进入等待用户操作状态。
  void enterWaitingForUserAfterCurrentPrompt() =>
      _engine.enterWaitingForUser(afterCurrentPrompt: true);

  /// 用户交互（查词/翻译等）
  void onUserInteraction() => _engine.onUserInteraction();

  /// 下一句
  Future<void> nextSentence() async => _engine.nextSentence();

  /// 上一句
  Future<void> previousSentence() async => _engine.previousSentence();

  /// 跳转到指定句子（0-based，供进度条拖动跳转使用）
  Future<void> goToSentence(int index) async => _engine.goToSentence(index);

  /// 录音按钮点击
  Future<void> onRecordButtonTapped() async => _engine.onRecordButtonTapped();

  /// 录音回放按钮点击
  Future<void> togglePlayback() async => _engine.togglePlayback();

  /// 为播放录音回放做准备。
  void prepareForPlayback() => _engine.prepareForPlayback();

  /// 手动开始录音
  void startManualRecording() => _engine.startManualRecording();

  /// 手动停止录音
  Future<void> stopRecording() async => _engine.stopRecording();

  /// 播放录音回放
  Future<void> playRecording() async => _engine.playRecording();

  /// 停止录音回放
  Future<void> stopPlayback() async => _engine.stopPlayback();

  /// 当前媒体会话的意群区间播放；音频会话保持既有播放路径，因此不暴露实现。
  SenseGroupRangePlayback? get senseGroupRangePlayback =>
      _senseGroupRangePlayback;

  /// 快进倒计时
  void fastForwardInterval() => _engine.fastForwardInterval();

  /// 暂停倒计时
  void pauseInterval() => _engine.pauseInterval();

  /// 恢复倒计时
  void resumeInterval() => _engine.resumeInterval();

  /// 重播当前句子
  Future<void> replayCurrentSentence() async => _engine.replayCurrentSentence();

  /// 停止会话
  void stopSession() => _engine.stopSession();

  /// 释放资源
  void disposeSession() {
    _playback.unbindLockScreen();
    _engine.stopSession();
    ref.read(speechRecordingControllerProvider.notifier).fullReset();
  }

  /// 应用会话内设置变更，并立即按新配置重建当前句流程。
  ///
  /// 设置面板是即时写回 Provider 的，因此这里不能等弹窗关闭后再处理。
  Future<void> applySettingsChange() async {
    ref
        .read(speechRecordingControllerProvider.notifier)
        .setManualMode(_engine.config.isManualMode());
    if (_engine.willEnterWaitingAfterCurrentPrompt) {
      return;
    }
    // 等待态只刷新当前句配置，不应立刻自动重播。
    await _engine.restartCurrentSentence(
      autoplay: state.phase is! WaitingForUser,
    );
  }

  /// 暂停学习计时（完成弹窗显示时调用）
  // ignore: use super method directly
  void pauseTimer() => pauseStudyTimer();

  // ========== 书签 & 进度 ==========

  /// 切换当前句子的收藏标记
  Future<void> toggleCurrentBookmark() async {
    if (_sentences.isEmpty) return;
    final idx = state.sentenceIndex;
    final s = _sentences[idx];
    final wasBookmarked = s.isBookmarked;
    _sentences[idx] = s.copyWith(isBookmarked: !wasBookmarked);
    state = state.copyWith(currentSentenceBookmarked: !wasBookmarked);

    final bookmarkDao = ref.read(bookmarkDaoProvider);
    if (wasBookmarked) {
      await bookmarkDao.removeBookmark(_engine.config.audioItemId, s.index);
    } else {
      await BookmarkManager.addBookmarkToDb(
        _engine.config.audioItemId,
        s,
        dao: bookmarkDao,
      );
    }
  }

  /// 保存断点
  Future<void> saveBreakpoint({required bool isFreePlay}) async {
    await ref
        .read(learningProgressNotifierProvider.notifier)
        .saveShadowingSentenceIndex(
          _engine.config.audioItemId,
          state.sentenceIndex,
          isFreePlay: isFreePlay,
        );
  }

  /// 清除断点
  Future<void> clearBreakpoint({required bool isFreePlay}) async {
    await ref
        .read(learningProgressNotifierProvider.notifier)
        .saveShadowingSentenceIndex(
          _engine.config.audioItemId,
          null,
          isFreePlay: isFreePlay,
        );
  }

  /// 递增遍数统计
  Future<void> incrementPassCount() async {
    await ref
        .read(learningProgressNotifierProvider.notifier)
        .incrementShadowingPassCount(_engine.config.audioItemId);
  }

  /// 标记当前子步骤完成
  Future<void> completeSubStage() async {
    await ref
        .read(learningProgressNotifierProvider.notifier)
        .completeCurrentSubStage(_engine.config.audioItemId);
  }

  /// 退出学习模式
  Future<void> exitLearningMode() async {
    if (_sessionPrepared) {
      ref.read(analyticsServiceProvider).track(Events.listenRepeatComplete, {
        ...ref.audioEventParams(_engine.config.audioItemId),
        EventParams.totalSentences: _sentences.length,
      });
    }
    disposeSession();
    await _senseGroupRangePlayback?.cancel();
    await disposeStudyTask(ref);
    if (_usesMediaEngine) {
      final mediaEngine = _ownedMediaEngine;
      final mediaGeneration = _ownedMediaGeneration;
      if (mediaEngine != null && mediaGeneration != null) {
        await _releaseOwnedMediaEngine(mediaEngine, mediaGeneration);
      }
    }
    _mediaSessionReady = false;
    _usesMediaEngine = false;
    _ownedMediaEngine = null;
    _ownedMediaGeneration = null;
    _senseGroupRangePlayback = null;
    _sessionPrepared = false;
    state = state.copyWith(usesMediaEngine: false);
  }

  // ========== 数据访问 ==========

  /// 当前句子
  Sentence? get currentSentence =>
      _sentences.isNotEmpty && state.sentenceIndex < _sentences.length
      ? _sentences[state.sentenceIndex]
      : null;

  /// 当前 promptId
  String get currentPromptId => _sessionPrepared
      ? _engine.currentPromptId
      : 'lar:pending:${state.sentenceIndex}';

  /// 当前跟读流程是否已经完成配置，可安全接收播放与设置操作。
  bool get isSessionPrepared => _sessionPrepared;

  /// 当前配置
  RepeatFlowConfig get config => _engine.config;

  /// 当前句子索引
  int get currentIndex => state.sentenceIndex;

  /// 句子列表
  List<Sentence> get sentences => List.unmodifiable(_sentences);

  /// 仅释放仍由指定 generation 持有的媒体，避免旧异步回调释放新会话。
  Future<void> _releaseOwnedMediaEngine(
    MediaEngine mediaEngine,
    int generation,
  ) async {
    if (!identical(_ownedMediaEngine, mediaEngine) ||
        _ownedMediaGeneration != generation) {
      return;
    }
    _ownedMediaEngine = null;
    _ownedMediaGeneration = null;
    await mediaEngine.releaseFromScreen();
  }

  // ========== Engine 回调实现 ==========

  /// Engine 状态变化 → 更新 Riverpod state
  void _onEngineStateChanged(RepeatFlowState flowState) {
    final isBookmarked =
        _sentences.isNotEmpty && flowState.sentenceIndex < _sentences.length
        ? _sentences[flowState.sentenceIndex].isBookmarked
        : false;
    state = ListenAndRepeatSessionState.fromFlowState(
      flowState,
      isFreePlay: _isFreePlay,
      currentSentenceBookmarked: isBookmarked,
      usesMediaEngine: _usesMediaEngine,
    );
    final interval = flowState.phase is WaitingInterval;
    final active = flowState.phase is PlayingPrompt || interval;
    _playback.setSessionActive(active);
    _playback.setProgressFrozen(interval);
  }

  /// 播放句子
  Future<void> _playSentence(Sentence sentence, int flowToken) async {
    final driver = _playback;
    final sessionId = driver.newSession();
    await driver.setSpeed(
      ref.read(listenAndRepeatSettingsProvider).playbackSpeed,
    );
    await driver.playSentence(sentence, sessionId);
    if (!driver.recordsStudyEventsInternally &&
        driver.isActiveSession(sessionId)) {
      studyEventRecorder?.onSentencePlayed(sentence);
    }
  }

  /// 开始录音
  void _startRecording({
    required String promptId,
    required String referenceText,
    required Duration maxDuration,
    Duration? referenceDuration,
  }) {
    final controller = ref.read(speechRecordingControllerProvider.notifier);
    controller.setMaxRecordingDuration(maxDuration);
    unawaited(
      controller.startRecording(
        promptId: promptId,
        referenceText: referenceText,
        referenceDuration: referenceDuration,
      ),
    );
  }

  /// 取消录音
  Future<void> _cancelRecording() async {
    await ref
        .read(speechRecordingControllerProvider.notifier)
        .cancelActiveRecording();
  }

  /// 停止录音并评估
  Future<void> _stopAndEvaluate({required String referenceText}) async {
    await ref
        .read(speechRecordingControllerProvider.notifier)
        .stopAndEvaluate(referenceText: referenceText);
  }

  /// 清除录音数据
  void _clearRecording() {
    ref.read(speechRecordingControllerProvider.notifier).clearRecording();
  }

  /// 设置录音最大时长
  void _setMaxRecordingDuration(Duration duration) {
    ref
        .read(speechRecordingControllerProvider.notifier)
        .setMaxRecordingDuration(duration);
  }

  /// 是否检测到语音
  bool _hasDetectedSpeech() {
    return ref.read(speechRecordingControllerProvider).hasDetectedSpeech;
  }

  /// 录音状态变化 → 桥接到 engine
  void _onRecordingStateChanged(
    SpeechRecordingState? prev,
    SpeechRecordingState next,
  ) {
    if (prev == null) return;

    if (prev.phase != next.phase) {
      AppLogger.log(
        'L&R Rec',
        '${prev.phase.name} → ${next.phase.name} | '
            'attempt=${next.currentAttempt != null} | '
            'score=${next.currentAttempt?.score}',
      );
    }

    // 评估完成 → 通知 engine（有 ASR: processing→idle，无 ASR: speaking→idle）
    if (prev.phase != SpeechRecordingPhase.idle &&
        next.phase == SpeechRecordingPhase.idle &&
        next.currentAttempt != null) {
      final attempt = next.currentAttempt!;
      _engine.onRecordingFinished(attempt.filePath, attempt.score);
      ref
          .read(usageTrackerProvider)
          .record(
            UsageEvent.recordingCompleted,
            analyticsParams: {
              ...ref.audioEventParams(_engine.config.audioItemId),
              EventParams.mode: 'listen_repeat',
              if (attempt.score != null) EventParams.score: attempt.score!,
            },
          );
    }

    // 录音取消/超时 → 通知 engine
    if (state.phase is Recording &&
        next.phase == SpeechRecordingPhase.idle &&
        next.currentAttempt == null) {
      _engine.onRecordingCancelled();
    }
  }
}
