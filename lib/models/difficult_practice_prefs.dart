/// 难句补练 / 收藏句复习「用户偏好」持久化模型
///
/// 业界标准的「默认值 + 记住用户修改」偏好持久化:单一真相源,typed,
/// **全字段可空**——`null` 表示「用户没碰过,用默认值」,非空表示「用户显式设过」。
///
/// 速度的默认值是**动态**的(按难度/阶段算,复习轮次会自动回升),因此速度覆盖为
/// `null` 时在 [resolve] 时取传入的智能默认 [smartSpeed];用户显式设过才存值,
/// 从而既记住手动改动、又不冻结智能默认。停顿/遍数/控制模式默认是静态的,同样
/// 用「可空覆盖」统一表达,缺省回退各自静态默认。
///
/// 对应目标模型 [DifficultPracticeSettings](难句补练/收藏句复习共用);其
/// fixedPause/multiplier 的合法档位复用 [IntensiveListenSettings] 的选项列表。
library;

import '../utils/playback_speed.dart';
import 'difficult_practice_settings.dart';
import 'intensive_listen_settings.dart';

/// 难句补练 / 收藏句复习用户偏好覆盖(不可变,全字段可空)。
///
/// 字段对应 [DifficultPracticeSettings] 的可改项;`null` = 用默认值。
class DifficultPracticePrefs {
  /// 控制模式覆盖(`null`=auto)。
  final ShadowingControlMode? controlMode;

  /// 盲听循环次数覆盖(`null`=1)。
  final int? blindListenRepeatCount;

  /// 跟读循环次数覆盖(`null`=3)。
  final int? shadowReadingRepeatCount;

  /// 停顿模式覆盖(`null`=smart)。
  final PauseMode? pauseMode;

  /// 固定间隔秒数覆盖(`null`=3)。
  final int? fixedPauseSeconds;

  /// 句长倍数覆盖(`null`=2.0)。
  final double? pauseMultiplier;

  /// 播放速度覆盖(`null`=用智能默认,见 [resolve])。
  final double? playbackSpeed;

  const DifficultPracticePrefs({
    this.controlMode,
    this.blindListenRepeatCount,
    this.shadowReadingRepeatCount,
    this.pauseMode,
    this.fixedPauseSeconds,
    this.pauseMultiplier,
    this.playbackSpeed,
  });

  /// 空偏好(用户未改动任何字段)。
  const DifficultPracticePrefs.empty()
    : controlMode = null,
      blindListenRepeatCount = null,
      shadowReadingRepeatCount = null,
      pauseMode = null,
      fixedPauseSeconds = null,
      pauseMultiplier = null,
      playbackSpeed = null;

  /// 把偏好叠加到默认值,得到本次会话生效的完整 [DifficultPracticeSettings]。
  ///
  /// [smartSpeed] 为按当前难度/阶段算出的动态默认速度;偏好未设速度时用它。
  /// 其余字段缺省回退 [DifficultPracticeSettings] 各自静态默认。
  DifficultPracticeSettings resolve({required double smartSpeed}) =>
      DifficultPracticeSettings(
        controlMode: controlMode ?? ShadowingControlMode.auto,
        blindListenRepeatCount: blindListenRepeatCount ?? 1,
        shadowReadingRepeatCount: shadowReadingRepeatCount ?? 3,
        pauseMode: pauseMode ?? PauseMode.smart,
        fixedPauseSeconds: fixedPauseSeconds ?? 3,
        pauseMultiplier: pauseMultiplier ?? 2.0,
        playbackSpeed: playbackSpeed ?? smartSpeed,
      );

  /// 返回叠加 [other] 非空字段后的新偏好(用于细粒度 setter:只改传入的字段)。
  ///
  /// 注意:仅覆盖传入的**非空**字段,无法把某字段重置回 `null`——本 app
  /// 无「清除偏好」入口,用户只会从默认改成具体值或在具体值间切换。
  DifficultPracticePrefs copyWith({
    ShadowingControlMode? controlMode,
    int? blindListenRepeatCount,
    int? shadowReadingRepeatCount,
    PauseMode? pauseMode,
    int? fixedPauseSeconds,
    double? pauseMultiplier,
    double? playbackSpeed,
  }) => DifficultPracticePrefs(
    controlMode: controlMode ?? this.controlMode,
    blindListenRepeatCount:
        blindListenRepeatCount ?? this.blindListenRepeatCount,
    shadowReadingRepeatCount:
        shadowReadingRepeatCount ?? this.shadowReadingRepeatCount,
    pauseMode: pauseMode ?? this.pauseMode,
    fixedPauseSeconds: fixedPauseSeconds ?? this.fixedPauseSeconds,
    pauseMultiplier: pauseMultiplier ?? this.pauseMultiplier,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
  );

  /// 序列化为稀疏 JSON(只写非空字段:缺省即「用默认」)。
  Map<String, dynamic> toJson() => {
    if (controlMode != null) 'controlMode': controlMode!.name,
    if (blindListenRepeatCount != null)
      'blindListenRepeatCount': blindListenRepeatCount,
    if (shadowReadingRepeatCount != null)
      'shadowReadingRepeatCount': shadowReadingRepeatCount,
    if (pauseMode != null) 'pauseMode': pauseMode!.name,
    if (fixedPauseSeconds != null) 'fixedPauseSeconds': fixedPauseSeconds,
    if (pauseMultiplier != null) 'pauseMultiplier': pauseMultiplier,
    if (playbackSpeed != null) 'playbackSpeed': playbackSpeed,
  };

  /// 防御性解析:字段缺失/类型错/越档一律视作未设(`null`),回退各自默认。
  factory DifficultPracticePrefs.fromJson(Map<String, dynamic> json) =>
      DifficultPracticePrefs(
        controlMode: _parseControlMode(json['controlMode']),
        blindListenRepeatCount: _parseRepeatCount(
          json['blindListenRepeatCount'],
        ),
        shadowReadingRepeatCount: _parseRepeatCount(
          json['shadowReadingRepeatCount'],
        ),
        pauseMode: _parsePauseMode(json['pauseMode']),
        fixedPauseSeconds: _parseFixedPauseSeconds(json['fixedPauseSeconds']),
        pauseMultiplier: _parsePauseMultiplier(json['pauseMultiplier']),
        playbackSpeed: _parseSpeed(json['playbackSpeed']),
      );

  /// 速度:归一化到统一档位;非 num 视作未设。
  static double? _parseSpeed(dynamic raw) =>
      raw is num ? normalizePlaybackSpeed(raw.toDouble()) : null;

  /// 控制模式:合法枚举名才认,否则未设。
  static ShadowingControlMode? _parseControlMode(dynamic raw) => raw is String
      ? ShadowingControlMode.values.where((e) => e.name == raw).firstOrNull
      : null;

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

  /// 循环次数:`0`(∞)或有限次数上限 50;超过 50 截到 50;其余视作未设。
  static int? _parseRepeatCount(dynamic raw) {
    if (raw is! int) return null;
    if (raw == 0) return 0;
    if (raw < 1) return null;
    return raw > 50 ? 50 : raw;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DifficultPracticePrefs &&
          runtimeType == other.runtimeType &&
          controlMode == other.controlMode &&
          blindListenRepeatCount == other.blindListenRepeatCount &&
          shadowReadingRepeatCount == other.shadowReadingRepeatCount &&
          pauseMode == other.pauseMode &&
          fixedPauseSeconds == other.fixedPauseSeconds &&
          pauseMultiplier == other.pauseMultiplier &&
          playbackSpeed == other.playbackSpeed;

  @override
  int get hashCode => Object.hash(
    controlMode,
    blindListenRepeatCount,
    shadowReadingRepeatCount,
    pauseMode,
    fixedPauseSeconds,
    pauseMultiplier,
    playbackSpeed,
  );
}
