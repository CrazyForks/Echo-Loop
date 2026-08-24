import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_localizations.dart';
import 'utils/time_format.dart';
import 'utils/echo_loop_scroll_behavior.dart';
import 'database/app_database.dart';
import 'database/providers.dart';
import 'database/migration/sp_to_drift_migration.dart';
import 'providers/package_info_provider.dart';
import 'providers/dictionary_provider.dart';
import 'providers/download_provider.dart';
import 'providers/pronunciation/pronunciation_providers.dart';
import 'providers/settings_provider.dart';
import 'providers/startup_readiness_provider.dart';
import 'router/app_router.dart';
import 'services/bundled_example_installer.dart';
import 'services/temp_cleanup_service.dart';
import 'theme/app_theme.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'config/api_config.dart';
import 'config/auth_config.dart' as auth_config;
import 'config/revenuecat_config.dart' as revenuecat_config;
import 'config/paddle_config.dart' as paddle_config;
import 'providers/review_reminder_provider.dart';
import 'services/notification_tap_router_bridge.dart';
import 'package:firebase_core/firebase_core.dart';
import 'analytics/analytics_providers.dart';
import 'analytics/analytics_service.dart';
import 'analytics/channels/log_only_channel.dart';
import 'analytics/consent_manager.dart';
import 'analytics/permission_snapshot.dart';
import 'services/network_permission_trigger.dart';
import 'services/user_id_service.dart';
import 'firebase_options.dart';
import 'providers/learning_settings_provider.dart';
import 'providers/tts/kokoro_model_provider.dart';
import 'providers/tts/piper_model_provider.dart';
import 'providers/tts/tts_settings_provider.dart';
import 'providers/intensive_listen_prefs_provider.dart';
import 'providers/blind_listen_prefs_provider.dart';
import 'providers/retell_prefs_provider.dart';
import 'providers/difficult_practice_prefs_provider.dart';
import 'providers/new_user_guide_provider.dart';
import 'providers/offline_asr_settings_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'services/asr/asr_model_manager.dart';
import 'services/app_logger.dart';
import 'services/startup_trace.dart';
import 'services/media_kit_debug_initializer.dart';
import 'services/tts/tts_cache_store.dart';
import 'utils/app_data_dir.dart';
import 'services/speech_practice_platform.dart';
import 'services/storage_migration_service.dart';
import 'services/background_audio_handler.dart';
import 'features/official_collections/data/official_catalog_service.dart';
import 'features/official_collections/data/trigger_official_sync.dart';
import 'features/official_collections/download/official_download_notifier.dart';
import 'features/onboarding_survey/data/onboarding_survey_storage.dart';
import 'features/onboarding_survey/providers/onboarding_survey_provider.dart';
import 'features/auth/providers/auth_providers.dart';
import 'features/auth/supabase_startup_gate.dart';
import 'features/remote_config/remote_config_providers.dart';
import 'features/remote_config/remote_config_service.dart';
import 'features/subscription/providers/subscription_controller.dart';
import 'features/subscription/providers/subscription_plans_provider.dart';

/// main() 与首帧后启动编排器之间的单次信号。
///
/// 在真实进程中由 main() 在 Drift 迁移完成后释放；Widget 测试未经过 main()
/// 时为 null，应用会直接视作本地数据已就绪。
Completer<void>? _localDataReadyCompleter;

/// Firebase、Supabase、RevenueCat 与分析通道后台初始化完成的单次信号。
Completer<void>? _thirdPartyReadyCompleter;

void main() async {
  final startupTrace = StartupTrace();
  registerStartupTrace(startupTrace);
  startupTrace.mark('dart_main_enter');
  WidgetsFlutterBinding.ensureInitialized();
  startupTrace.mark('flutter_binding_ready');
  if (!kIsWeb) {
    startupTrace.runSync('media_kit_initialize', ensureMediaKitInitialized);
  } else {
    startupTrace.mark(
      'step_skipped',
      fields: {'step': 'media_kit_initialize', 'reason': 'web'},
    );
  }
  startupTrace.runSync('timeago_initialize', initTimeago);

  final packageInfo = await startupTrace.run(
    'package_info',
    PackageInfo.fromPlatform,
  );

  // 检查是否处于演示模式
  final prefs = await startupTrace.run(
    'shared_preferences',
    SharedPreferences.getInstance,
  );
  // 路由 observer 在首帧构建时即会读取 analytics。先安装纯日志实现，第三方
  // 埋点 SDK 在后续后台阶段成功初始化后再替换，避免首帧依赖 Firebase/PostHog。
  initAnalytics(
    AnalyticsService(channel: LogOnlyChannel(), consent: ConsentManager(prefs)),
  );
  final isDemoMode = prefs.getBool('demo_mode') ?? false;

  // 远程配置：启动期只同步读取本地缓存/默认值，不触发网络请求，避免网络慢阻塞首帧。
  // 下游 UI 只读取 provider 暴露的 resolved config；远端刷新由 MainShell 首帧后后台执行。
  final initialRemoteConfig = RemoteConfigService.create(
    prefs: prefs,
    appVersion: packageInfo.version,
  ).loadInitialFromCache();

  // 首次启动检测：哨兵 key `first_launch_done` 不存在即视为首次启动，
  // 立即写入 true。后续所有启动都会读到该 key = true，即非首启。
  // 注意：该机制从此版本引入，老用户升级时哨兵同样缺失，会被当作首启。
  // 需要业务层额外用数据是否为空等 gate 兜底区分升级用户。
  final isFirstLaunch = !(prefs.getBool('first_launch_done') ?? false);
  if (isFirstLaunch) {
    await startupTrace.run(
      'first_launch_marker_write',
      () => prefs.setBool('first_launch_done', true),
    );
  }

  // Onboarding 问卷"是否已完成"同步预读：GoRouter redirect 是同步函数，
  // 必须在 main() 阶段拿到值，否则启动闪屏期间 redirect 失效。
  // 用 `onboarding_completed_at_ms` 存在性判定，不引入冗余 bool key。
  final onboardingCompleted = OnboardingSurveyStorage.readIsCompletedSync(
    prefs,
  );

  // 旧“语音识别总开关”迁移到两个练习评分开关，须在学习设置预读前完成。
  await startupTrace.run(
    'legacy_offline_asr_settings_migration',
    () => migrateLegacyOfflineAsrEnabledToRatingSettings(prefs),
  );

  // 学习设置（自动跳过复述）同步预读：plan / progress 启动期就需要拿到值。
  final initialLearningSettings = LearningSettings.fromPrefsSync(prefs);
  // 清理历史 SP key（开发期数据卫生，幂等无副作用）。
  await startupTrace.run(
    'legacy_learning_settings_cleanup',
    () => cleanupLegacyLearningSettingsKeys(prefs),
  );

  // Android 不再提供系统语音入口；先迁移历史偏好，再同步预读。
  if (!kIsWeb && Platform.isAndroid) {
    await startupTrace.run(
      'android_tts_settings_migration',
      () => migrateAndroidPlatformTtsToEchoLoop(prefs),
    );
  }

  // 语音合成设置（引擎/口音）同步预读：闪卡翻面等同步发音路径需立即拿到口音，
  // 避免异步 hydrate 前先用默认美音发声。
  final initialTtsSettings = TtsSettings.fromPrefsSync(prefs);

  // 各学习子阶段用户偏好(按槽位)同步预读:入口弹窗 / 播放器进入时需立即拿到记忆值。
  final initialIntensiveListenPrefs = intensiveListenPrefsFromPrefsSync(prefs);
  final initialBlindListenPrefs = blindListenPrefsFromPrefsSync(prefs);
  final initialRetellPrefs = retellPrefsFromPrefsSync(prefs);
  final initialDifficultPracticePrefs = difficultPracticePrefsFromPrefsSync(
    prefs,
  );

  // 界面语言同步预读：让首帧 MaterialApp.locale 直接拿到用户已选语言，
  // 避免"先按系统语言渲染、再 hydrate 切到用户设置"的闪烁。
  final initialUiLocale = readInitialUiLocaleSync(prefs);
  // AI 转录「自动合并短句」同步预读：让转录弹窗首帧直接拿到上次选择，
  // 避免在 AppSettings 异步 hydrate 前先读到默认 true。
  final initialAiTranscriptionAutoMergeEnabled =
      readInitialAiTranscriptionAutoMergeEnabledSync(prefs);

  // 初始化数据库（演示模式使用独立数据库文件）
  final dbFileName = isDemoMode ? 'echo_loop_demo.db' : 'echo_loop.db';
  final database = AppDatabase(openConnectionWithName(dbFileName));
  initAppDatabase(database);
  startupTrace.mark(
    'database_instance_registered',
    fields: {'demoMode': isDemoMode},
  );

  // 至此仅完成了绑定、同步 UI 偏好和数据库对象注册。马上交给 Flutter 绘制
  // 真实应用；下方所有会触及文件、数据库或第三方 SDK 的任务都在首帧后继续。
  _localDataReadyCompleter = Completer<void>();
  _thirdPartyReadyCompleter = Completer<void>();
  startupTrace.mark('run_app_invoked');
  runApp(
    PostHogWidget(
      child: ProviderScope(
        overrides: [
          packageInfoProvider.overrideWithValue(packageInfo),
          isFirstLaunchProvider.overrideWithValue(isFirstLaunch),
          sharedPreferencesProvider.overrideWithValue(prefs),
          initialOnboardingCompletedProvider.overrideWithValue(
            onboardingCompleted,
          ),
          initialLearningSettingsProvider.overrideWithValue(
            initialLearningSettings,
          ),
          initialTtsSettingsProvider.overrideWithValue(initialTtsSettings),
          initialIntensiveListenPrefsProvider.overrideWithValue(
            initialIntensiveListenPrefs,
          ),
          initialBlindListenPrefsProvider.overrideWithValue(
            initialBlindListenPrefs,
          ),
          initialRetellPrefsProvider.overrideWithValue(initialRetellPrefs),
          initialDifficultPracticePrefsProvider.overrideWithValue(
            initialDifficultPracticePrefs,
          ),
          initialUiLocaleProvider.overrideWithValue(initialUiLocale),
          initialAiTranscriptionAutoMergeEnabledProvider.overrideWithValue(
            initialAiTranscriptionAutoMergeEnabled,
          ),
          initialRemoteConfigProvider.overrideWithValue(initialRemoteConfig),
        ],
        child: const EchoLoopApp(),
      ),
    ),
  );

  // 明确让出 event loop，确保上面的 runApp 已提交第一帧；不能依赖后续异步
  // 方法“通常会 yield”的偶然行为，否则其同步前置工作仍可能拖慢首帧。
  await startupTrace.run('wait_for_first_frame', () {
    return WidgetsBinding.instance.endOfFrame;
  });

  // 日志落盘与目录迁移都会触及文件系统，不能再占用首帧路径。追踪器在此之前
  // 仍会输出到控制台；落盘初始化完成后接管后续结构化启动日志。
  try {
    await startupTrace.run('app_log_file_sink', () async {
      await AppLogger.initFileSink(await appLogFilePath());
    });
  } catch (_) {
    // 与既有逻辑一致：日志落盘失败不阻断启动。
  } finally {
    startupTrace.attachLogger();
  }
  try {
    await startupTrace.run(
      'data_directory_migration',
      migrateToAppSupportDirectory,
    );
  } catch (error) {
    AppLogger.log('App', '数据目录迁移失败，下次启动重试: $error');
  }

  // 执行 SP → Drift 迁移（仅对生产数据库）
  if (!isDemoMode) {
    final migration = SpToDriftMigration(
      database,
      prefs,
      subtitleLoader: defaultSubtitleLoader,
    );
    try {
      await startupTrace.run('shared_preferences_to_drift_migration', () {
        return migration.migrate();
      });
    } catch (e) {
      print('SP → Drift 迁移失败，下次启动重试: $e');
    }

    // 首次启动时安装内置示例内容
    try {
      await startupTrace.run('bundled_examples_install', () {
        return BundledExampleInstaller(database, prefs).installOnFirstLaunch();
      });
    } catch (e) {
      print('内置示例安装失败: $e');
    }
  }

  // 仅在本地数据迁移完成后允许主导航树创建业务页面。
  startupTrace.mark('local_data_ready');
  _localDataReadyCompleter?.complete();

  await startupTrace.run('background_audio_handler_initialize', () {
    return initEchoLoopAudioHandler();
  });

  // iOS: 通过原生网络栈触发系统网络权限弹窗。
  // 启动时立即触发（包括 Onboarding 期间的新用户），原因：埋点上报
  // （app_permission_snapshot / onboarding_survey_shown 等）依赖网络通畅，
  // 推迟会丢失事件。系统弹窗由 OS 决定具体呈现时机，可能延后。
  if (!kIsWeb && Platform.isIOS) {
    startupTrace.mark(
      'detached_scheduled',
      fields: {'step': 'ios_network_permission_trigger'},
    );
    unawaited(NetworkPermissionTrigger.trigger(prefs, apiBaseUrl));
  }

  // 初始化 Firebase
  try {
    await startupTrace.run('firebase_initialize', () {
      return Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    });
  } catch (error, stackTrace) {
    // Firebase 只服务于非核心能力，初始化失败不可阻断学习主流程或后续 SDK。
    AppLogger.log('Startup', 'firebase_initialize_failed error=$error');
    AppLogger.log('Startup', stackTrace.toString());
  }

  // 初始化 Supabase（认证 + 未来云同步用）
  //
  // 仅在 --dart-define 注入了 SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY 时才初始化；
  // 未配置时跳过，登录功能不可用但 app 仍可匿名运行（渐进式登录策略）。
  // Session 默认走 SharedPreferences 持久化，重启自动恢复。
  // 已恢复的登录用户 ID（若有）。用于给 RevenueCat configure 直接带上 appUserID，
  // 让已登录老用户冷启动跳过匿名态；未登录 / 未配置认证时为 null。
  String? restoredUserId;
  if (auth_config.isAuthConfigured) {
    try {
      await startupTrace.run('supabase_initialize', () {
        return Supabase.initialize(
          url: auth_config.supabaseUrl,
          anonKey: auth_config.supabasePublishableKey,
        );
      });
      SupabaseStartupGate.markReady();
      // Supabase 启动时自动从 SharedPreferences 恢复上次 session；此处读回恢复的用户 ID。
      restoredUserId = Supabase.instance.client.auth.currentSession?.user.id;
    } catch (e) {
      AppLogger.log('App', 'Supabase 初始化失败，认证功能不可用: $e');
    }
  } else {
    startupTrace.mark(
      'step_skipped',
      fields: {'step': 'supabase_initialize', 'reason': 'not_configured'},
    );
    AppLogger.log(
      'App',
      'Supabase 未配置（缺 SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY），跳过初始化',
    );
  }

  // 初始化 RevenueCat（IAP 订阅）
  //
  // 仅在 --dart-define 注入了当前平台的 REVENUECAT_API_KEY_* 时才初始化；
  // 未配置时跳过，订阅功能不可用但 app 仍可匿名运行。
  // 用户身份绑定（Purchases.logIn）由 SubscriptionController 监听登录态后处理，
  // 这里只做 SDK 配置。
  if (revenuecat_config.useLocalStoreKit) {
    startupTrace.mark(
      'step_skipped',
      fields: {'step': 'revenuecat_initialize', 'reason': 'local_storekit'},
    );
    // 本地 StoreKit 测试模式：**不初始化 RevenueCat**，购买走 in_app_purchase
    // 直连 .storekit，避免本地交易被 RC SDK 捕获上报（不污染 RC Sandbox）。
    AppLogger.log('App', '本地 StoreKit 测试模式：跳过 RevenueCat 初始化');
  } else if (paddle_config.isPaddleCheckoutChannel) {
    startupTrace.mark(
      'step_skipped',
      fields: {'step': 'revenuecat_initialize', 'reason': 'paddle_direct'},
    );
    // direct 渠道（侧载 APK / 桌面）：不初始化 RC，购买走 Paddle Checkout、
    // 权益经后端 /api/entitlements 读回，**不初始化 RevenueCat SDK**。
    AppLogger.log('App', 'Paddle direct 渠道：跳过 RevenueCat 初始化（权益经后端读回）');
  } else if (revenuecat_config.isRevenueCatConfigured) {
    try {
      // Debug 构建打开 RevenueCat 详细日志，便于定位 Offerings 为空等问题。
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      // 若已有恢复的登录 session，直接以真实用户 ID 配置，跳过匿名态；
      // 否则匿名 configure（行为同旧版），后续由 SubscriptionController.logIn 绑定。
      final configuration = PurchasesConfiguration(
        revenuecat_config.revenueCatApiKey,
      );
      if (restoredUserId != null) {
        configuration.appUserID = restoredUserId;
      }
      await startupTrace.run('revenuecat_initialize', () {
        return Purchases.configure(configuration);
      });
      AppLogger.log(
        'App',
        restoredUserId != null
            ? 'RevenueCat 以已登录身份 configure（appUserID=$restoredUserId）'
            : 'RevenueCat 匿名 configure',
      );
    } catch (e) {
      AppLogger.log('App', 'RevenueCat 初始化失败，订阅功能不可用: $e');
    }
  } else {
    startupTrace.mark(
      'step_skipped',
      fields: {'step': 'revenuecat_initialize', 'reason': 'not_configured'},
    );
    AppLogger.log('App', 'RevenueCat 未配置（缺平台 API Key），跳过初始化');
  }

  // 初始化用户 ID（SecureStorage 持久化，卸载重装可恢复）
  final userId = await startupTrace.run(
    'user_id_initialize',
    () => initUserIdService(prefs),
  );

  // 初始化分析服务（根据 geo 选择 Firebase/友盟/Log 通道）
  late final AnalyticsService analyticsService;
  try {
    analyticsService = await startupTrace.run(
      'analytics_initialize',
      () => initAnalyticsService(prefs, userId: userId),
    );
  } catch (error, stackTrace) {
    // 保留首帧前的日志通道，埋点失败不应影响学习与订阅之外的基础能力。
    AppLogger.log('Startup', 'analytics_initialize_failed error=$error');
    AppLogger.log('Startup', stackTrace.toString());
    analyticsService = AnalyticsService(
      channel: LogOnlyChannel(),
      consent: ConsentManager(prefs),
    );
  }
  initAnalytics(analyticsService);
  startupTrace.mark('third_party_services_ready');
  _thirdPartyReadyCompleter?.complete();

  // 上报 4 类系统授权状态（mic / speech / notification / network）：
  // super properties + person properties + app_permission_snapshot 三路写入。
  // 失败不影响启动；底层方法已各自做 consent gate + try/catch。
  try {
    await startupTrace.run('permission_snapshot_report', () async {
      final snapshot = await PermissionSnapshot.capture(prefs);
      await analyticsService.reportPermissionSnapshot(snapshot, prefs);
    });
  } catch (e) {
    AppLogger.log('App', '权限状态埋点失败: $e');
  }

  // 清理上次残留的录音临时文件（沙盒/tmp/ 中超过 60 秒的文件），不阻塞启动
  unawaited(cleanupRecordingTempFiles());
  startupTrace.mark(
    'detached_scheduled',
    fields: {'step': 'recording_temp_cleanup'},
  );

  // 清理超过 1 天的 PDF 分享临时目录（分享后不能立即删，见 temp_cleanup_service）
  unawaited(cleanupStalePdfExportTemp());
  startupTrace.mark(
    'detached_scheduled',
    fields: {'step': 'pdf_export_temp_cleanup'},
  );

  // 清理超过 1 天的百度网盘半下载临时文件，短期保留用于续传
  unawaited(cleanupStaleBaiduNetdiskTemp());
  startupTrace.mark(
    'detached_scheduled',
    fields: {'step': 'baidu_netdisk_temp_cleanup'},
  );

  // 启动后延迟清理 TTS 合成缓存（过期 + 超量 LRU），不拖首屏。
  Future.delayed(const Duration(seconds: 8), () {
    TtsCacheStore(
      resolveDao: () => database.ttsCacheDao,
      resolveCacheDir: getApplicationCacheDirectory,
    ).cleanup();
  });

  // 词典由 dictionaryProvider 管理下载和打开，
  // 在 EchoLoopApp.initState 中 eagerly read 触发初始化。

  // 离线 ASR 初始化（全平台）。
  // Android 固定 offline 后端，iOS/macOS 默认 platform 后端（可切换）。
  if (!kIsWeb) {
    final defaultBackend = Platform.isAndroid
        ? AsrBackend.offline
        : AsrBackend.platform;
    AppLogger.log(
      'App',
      'ASR: platform=${Platform.operatingSystem}, defaultBackend=${defaultBackend.name}',
    );
    final platform = SpeechPracticePlatform.instance;
    final ramBytes = platform.isSupported
        ? await startupTrace.run(
            'offline_asr_device_ram_read',
            platform.getDeviceRamBytes,
          )
        : 0;
    final modelManager = AsrModelManager();
    final recommendedModel = modelManager.recommendModel(ramBytes: ramBytes);
    modelManager.dispose();
    // 此推荐只用于日志和后续模型恢复；首帧的默认 provider 使用安全的
    // 保守模型，避免为了读取设备内存阻塞 runApp。
    AppLogger.log('App', 'ASR recommended model=${recommendedModel.id}');
  }

  // 清理上次运行残留的官方合集音频下载 tmp 文件（异步）
  unawaited(cleanupOfficialDownloadTmp());

  startupTrace.mark(
    'detached_scheduled',
    fields: {'step': 'official_download_tmp_cleanup'},
  );
}

class EchoLoopApp extends ConsumerStatefulWidget {
  const EchoLoopApp({super.key});

  @override
  ConsumerState<EchoLoopApp> createState() => _EchoLoopAppState();
}

class _EchoLoopAppState extends ConsumerState<EchoLoopApp>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationIntent>? _intentSubscription;
  ProviderSubscription<AsyncValue<Session?>>? _authSessionSubscription;
  late final ShowcaseView _showcase;
  bool _hasLoggedRouterCreated = false;
  bool _isLocalDataReady = false;
  bool _areThirdPartyServicesReady = false;

  @override
  void initState() {
    super.initState();
    activeStartupTrace?.mark('app_widget_init_state');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      activeStartupTrace?.mark('flutter_first_frame_rendered');
      unawaited(_startAfterLocalDataReady());
    });

    WidgetsBinding.instance.addObserver(this);

    // 新手引导 showcase 控制器全局注册（替代旧的 ShowCaseWidget InheritedWidget）。
    // 整段 tour 走完或被 dismiss 时，通过 GuideShowcaseBus 触发 controller 的
    // completeActiveFlow 标记已看并清空 active。
    _showcase = ShowcaseView.register(
      enableAutoScroll: true,
      onFinish: GuideShowcaseBus.fireEnd,
      onDismiss: (_) => GuideShowcaseBus.fireEnd(),
    );
  }

  /// 依次启动所有不属于首帧关键路径的本地预热任务。
  Future<void> _startAfterLocalDataReady() async {
    final ready = _localDataReadyCompleter;
    if (ready != null) {
      await ready.future;
    }
    if (!mounted) return;

    ref.read(startupReadinessProvider.notifier).markLocalDataReady();
    _isLocalDataReady = true;
    activeStartupTrace?.mark('main_navigation_released');

    // 下载注册表、词典和本地模型扫描都可能访问文件系统，统一放到首帧后。
    unawaited(startRegisteredDownloads(ref));
    unawaited(_restoreLocalModelStates());
    ref.read(dictionaryProvider);
    ref.read(pronunciationLibraryProvider);

    unawaited(_startThirdPartyDependentTasks());

    unawaited(
      ref.read(officialCatalogServiceProvider).loadCachedCatalog().then((_) {
        if (mounted) ref.invalidate(cachedCatalogProvider);
      }),
    );
    final bridge = ref.read(notificationTapRouterBridgeProvider);
    _intentSubscription = bridge.intents.listen(_handleNotificationIntent);
    final pendingIntent = bridge.takePendingIntent();
    if (pendingIntent != null) _handleNotificationIntent(pendingIntent);

    Future.delayed(
      const Duration(seconds: 3),
      () => _triggerCatalogSync(force: true),
    );
  }

  /// 等待后台 SDK 初始化完成后再创建其依赖的订阅与认证控制器。
  Future<void> _startThirdPartyDependentTasks() async {
    final ready = _thirdPartyReadyCompleter;
    if (ready != null) await ready.future;
    if (!mounted) return;
    _areThirdPartyServicesReady = true;

    // RevenueCat 与 Supabase 已完成后台串行初始化；现在才预热订阅状态，避免
    // SDK 未 configure 时页面或 controller 直接访问原生通道。
    ref.read(subscriptionControllerProvider);
    ref.read(subscriptionPlansProvider);
    ref.invalidate(supabaseSessionProvider);
    _authSessionSubscription = ref.listenManual<AsyncValue<Session?>>(
      supabaseSessionProvider,
      (previous, next) {
        unawaited(
          ref
              .read(authAnalyticsSyncProvider)
              .syncSessionChange(
                previous: previous?.valueOrNull,
                current: next.valueOrNull,
              ),
        );
      },
      fireImmediately: true,
    );
  }

  /// 在首帧提交后恢复本地模型状态，避免目录扫描阻塞应用进入学习页。
  Future<void> _restoreLocalModelStates() async {
    if (kIsWeb) {
      activeStartupTrace?.mark(
        'step_skipped',
        fields: {'step': 'local_model_state_recovery', 'reason': 'web'},
      );
      return;
    }

    final trace = activeStartupTrace;
    trace?.mark('local_model_recovery_scheduled');
    await _restoreModelState(
      step: 'offline_asr_initial_state_load',
      restore: () => ref
          .read(offlineAsrSettingsProvider.notifier)
          .restoreInitialStateFromDisk(),
    );
    await _restoreModelState(
      step: 'kokoro_initial_model_state_load',
      restore: () =>
          ref.read(kokoroModelProvider.notifier).restoreInitialStateFromDisk(),
    );
    await _restoreModelState(
      step: 'piper_initial_model_state_load',
      restore: () =>
          ref.read(piperModelProvider.notifier).restoreInitialStateFromDisk(),
    );
    trace?.mark('local_model_recovery_complete');
  }

  /// 执行单个模型域恢复；单项失败不能阻止后续域或影响应用使用。
  Future<void> _restoreModelState({
    required String step,
    required Future<void> Function() restore,
  }) async {
    final trace = activeStartupTrace;
    try {
      if (trace == null) {
        await restore();
      } else {
        await trace.run(step, restore);
      }
    } catch (error, stackTrace) {
      AppLogger.log(
        'Startup',
        'local_model_recovery_failed step=$step error=$error',
      );
      AppLogger.log('Startup', stackTrace.toString());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentSubscription?.cancel();
    _authSessionSubscription?.close();
    _showcase.unregister();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        if (_isLocalDataReady) {
          _triggerCatalogSync();
        }
        // 回前台时条件重对账订阅权益（E8）。单一来源下每次刷新都是真实后端请求
        // （不再有 RC SDK 客户端缓存兜着），且退款/退订分歧主要靠 E6/E7 在后端
        // 交互时被动收敛，故仅在状态陈旧 / 越过到期点 / 超过 24h 新鲜窗（兜住
        // 长期无后端流量的用户）时才回源，频繁切前台不盲查。
        if (_areThirdPartyServicesReady) {
          unawaited(
            ref.read(subscriptionControllerProvider.notifier).refreshIfStale(),
          );
          // 同时检查商店 storefront。跨区时立即撤下旧币种价格并重新读取商品；
          // 同区则遵循五分钟 TTL，避免每次短暂切后台都重复查询。
          unawaited(
            ref.read(subscriptionPlansProvider.notifier).refreshIfStale(),
          );
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 立即刷新 PostHog 埋点队列，避免 Application Backgrounded 等事件
        // 卡在内存队列里，App 被 OS 挂起 / 杀进程时丢失。
        // PostHog 默认 flushAt=20 / flushInterval=30s，单纯依赖默认策略
        // 在快速切后台场景容易丢。
        unawaited(Posthog().flush());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      // no-op
    }
  }

  /// 全局唯一同步入口；inflight + 2h 节流防止重复请求。
  /// updated 时由 helper 自动 loadLibrary + loadCollections + invalidate catalog。
  void _triggerCatalogSync({bool force = false}) {
    if (!mounted) return;
    unawaited(
      triggerOfficialSync(ref, force: force).then((outcome) {
        AppLogger.log('main', 'OfficialSync outcome=$outcome');
      }),
    );
  }

  void _handleNotificationIntent(NotificationIntent intent) {
    if (!mounted) return;
    switch (intent) {
      case OpenStudyTasks():
        ref.read(appRouterProvider).go(AppRoutes.study);
      case OpenFavorites():
        ref.read(appRouterProvider).go(AppRoutes.favorites);
      case OpenAudioLearningPlan(:final audioId):
        final router = ref.read(appRouterProvider);
        router.go(AppRoutes.study);
        router.push(AppRoutes.audioLearningPlan(audioId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(appRouterProvider);
    if (!_hasLoggedRouterCreated) {
      _hasLoggedRouterCreated = true;
      activeStartupTrace?.mark('router_created');
    }

    return MaterialApp.router(
      title: 'Echo Loop',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const EchoLoopScrollBehavior(),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      scaffoldMessengerKey: officialDownloadScaffoldMessengerKey,
    );
  }
}
