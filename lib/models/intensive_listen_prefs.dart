/// 逐句精听「用户偏好」持久化模型
///
/// 业界标准的「默认值 + 记住用户修改」偏好持久化：单一真相源,typed,
/// **全字段可空**——`null` 表示「用户没碰过,用默认值」,非空表示「用户显式设过」。
///
/// 速度的默认值是**动态**的(按难度/阶段算,复习轮次会自动回升),因此速度覆盖为
/// `null` 时在 [resolve] 时取传入的智能默认 [smartSpeed];用户显式设过才存值,
/// 从而既记住手动改动、又不冻结智能默认。停顿/遍数/控制模式默认是静态的,同样
/// 用「可空覆盖」统一表达,缺省回退各自静态默认。
///
/// 不再按复习轮次分 slot:停顿/遍数等显式偏好跨轮保留,速度未设(null)时仍按各轮
/// 难度 resolve 自动回升——既简单又保住核心动态行为。
library;

import '../utils/playback_speed.dart';
import 'intensive_listen_settings.dart';

/// 难句跟读入口的句子范围。
///
/// 该值只存于 `listenAndRepeat:*` 槽位；不属于播放器运行时设置，
/// 因此不会进入 [IntensiveListenSettings] 或任务页设置面板。
enum ListenAndRepeatScope { fullText, difficultOnly }

/// 逐句精听用户偏好覆盖(不可变,全字段可空)。
///
/// 字段对应 [IntensiveListenSettings] 的可改项;`null` = 用默认值。
class IntensiveListenPrefs {
  /// 播放速度覆盖(`null`=用智能默认,见 [resolve])。
  final double? playbackSpeed;

  /// 停顿模式覆盖(`null`=smart)。
  final PauseMode? pauseMode;

  /// 固定间隔秒数覆盖(`null`=3)。
  final int? fixedPauseSeconds;

  /// 句长倍数覆盖(`null`=2.0)。
  final double? pauseMultiplier;

  /// 控制模式覆盖(`null`=auto)。
  final ShadowingControlMode? controlMode;

  /// 每句循环次数覆盖(`null`=1)。
  final int? repeatCount;

  /// 难句跟读入口范围覆盖（`null`=默认仅难句）。
  final ListenAndRepeatScope? listenAndRepeatScope;

  const IntensiveListenPrefs({
    this.playbackSpeed,
    this.pauseMode,
    this.fixedPauseSeconds,
    this.pauseMultiplier,
    this.controlMode,
    this.repeatCount,
    this.listenAndRepeatScope,
  });

  /// 空偏好(用户未改动任何字段)。
  const IntensiveListenPrefs.empty()
    : playbackSpeed = null,
      pauseMode = null,
      fixedPauseSeconds = null,
      pauseMultiplier = null,
      controlMode = null,
      repeatCount = null,
      listenAndRepeatScope = null;

  /// 把偏好叠加到默认值,得到本次会话生效的完整 [IntensiveListenSettings]。
  ///
  /// [smartSpeed] 为按当前难度/阶段算出的动态默认速度;偏好未设速度时用它。
  /// [smartRepeatCount] 为动态默认遍数:逐句精听静态 1;难句跟读按难度算的目标遍数。
  IntensiveListenSettings resolve({
    required double smartSpeed,
    int smartRepeatCount = 1,
  }) => IntensiveListenSettings(
    playbackSpeed: playbackSpeed ?? smartSpeed,
    pauseMode: pauseMode ?? PauseMode.smart,
    fixedPauseSeconds: fixedPauseSeconds ?? 3,
    pauseMultiplier: pauseMultiplier ?? 2.0,
    controlMode: controlMode ?? ShadowingControlMode.auto,
    repeatCount: repeatCount ?? smartRepeatCount,
  );

  /// 返回叠加 [other] 非空字段后的新偏好(用于细粒度 setter:只改传入的字段)。
  ///
  /// 注意:仅覆盖 [other] 中**非空**的字段,无法把某字段重置回 `null`——本 app
  /// 无「清除偏好」入口,用户只会从默认改成具体值或在具体值间切换。
  IntensiveListenPrefs copyWith({
    double? playbackSpeed,
    PauseMode? pauseMode,
    int? fixedPauseSeconds,
    double? pauseMultiplier,
    ShadowingControlMode? controlMode,
    int? repeatCount,
    ListenAndRepeatScope? listenAndRepeatScope,
  }) => IntensiveListenPrefs(
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    pauseMode: pauseMode ?? this.pauseMode,
    fixedPauseSeconds: fixedPauseSeconds ?? this.fixedPauseSeconds,
    pauseMultiplier: pauseMultiplier ?? this.pauseMultiplier,
    controlMode: controlMode ?? this.controlMode,
    repeatCount: repeatCount ?? this.repeatCount,
    listenAndRepeatScope: listenAndRepeatScope ?? this.listenAndRepeatScope,
  );

  /// 序列化为稀疏 JSON(只写非空字段:缺省即「用默认」)。
  Map<String, dynamic> toJson() => {
    if (playbackSpeed != null) 'playbackSpeed': playbackSpeed,
    if (pauseMode != null) 'pauseMode': pauseMode!.name,
    if (fixedPauseSeconds != null) 'fixedPauseSeconds': fixedPauseSeconds,
    if (pauseMultiplier != null) 'pauseMultiplier': pauseMultiplier,
    if (controlMode != null) 'controlMode': controlMode!.name,
    if (repeatCount != null) 'repeatCount': repeatCount,
    if (listenAndRepeatScope != null)
      'listenAndRepeatScope': listenAndRepeatScope!.name,
  };

  /// 防御性解析:字段缺失/类型错/越档一律视作未设(`null`),回退各自默认。
  factory IntensiveListenPrefs.fromJson(Map<String, dynamic> json) =>
      IntensiveListenPrefs(
        playbackSpeed: _parseSpeed(json['playbackSpeed']),
        pauseMode: _parsePauseMode(json['pauseMode']),
        fixedPauseSeconds: _parseFixedPauseSeconds(json['fixedPauseSeconds']),
        pauseMultiplier: _parsePauseMultiplier(json['pauseMultiplier']),
        controlMode: _parseControlMode(json['controlMode']),
        repeatCount: _parseRepeatCount(json['repeatCount']),
        listenAndRepeatScope: _parseListenAndRepeatScope(
          json['listenAndRepeatScope'],
        ),
      );

  /// 速度:归一化到统一档位;非 num 视作未设。
  static double? _parseSpeed(dynamic raw) =>
      raw is num ? normalizePlaybackSpeed(raw.toDouble()) : null;

  /// 停顿模式:合法枚举名才认,否则未设。
  static PauseMode? _parsePauseMode(dynamic raw) => raw is String
      ? PauseMode.values.where((e) => e.name == raw).firstOrNull
      : null;

  /// 固定间隔:必须在可选档位内,否则未设。
  static int? _parseFixedPauseSeconds(dynamic raw) =>
      (raw is int && IntensiveListenSettings.fixedPauseOptions.contains(raw))
      ? raw
      : null;

  /// 倍数:必须在可选档位内,否则未设。
  static double? _parsePauseMultiplier(dynamic raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return IntensiveListenSettings.multiplierOptions.contains(value)
        ? value
        : null;
  }

  /// 控制模式:合法枚举名才认,否则未设。
  static ShadowingControlMode? _parseControlMode(dynamic raw) => raw is String
      ? ShadowingControlMode.values.where((e) => e.name == raw).firstOrNull
      : null;

  /// 循环次数:`0`(∞)或 `1-10` 合法;`>10` 截到 10;其余视作未设。
  static int? _parseRepeatCount(dynamic raw) {
    if (raw is! int) return null;
    if (raw == 0) return 0;
    if (raw < 1) return null;
    return raw > 10 ? 10 : raw;
  }

  static ListenAndRepeatScope? _parseListenAndRepeatScope(dynamic raw) =>
      raw is String
      ? ListenAndRepeatScope.values.where((e) => e.name == raw).firstOrNull
      : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntensiveListenPrefs &&
          runtimeType == other.runtimeType &&
          playbackSpeed == other.playbackSpeed &&
          pauseMode == other.pauseMode &&
          fixedPauseSeconds == other.fixedPauseSeconds &&
          pauseMultiplier == other.pauseMultiplier &&
          controlMode == other.controlMode &&
          repeatCount == other.repeatCount &&
          listenAndRepeatScope == other.listenAndRepeatScope;

  @override
  int get hashCode => Object.hash(
    playbackSpeed,
    pauseMode,
    fixedPauseSeconds,
    pauseMultiplier,
    controlMode,
    repeatCount,
    listenAndRepeatScope,
  );
}
