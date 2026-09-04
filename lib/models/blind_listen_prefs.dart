/// 全文盲听「用户偏好」持久化模型
///
/// 业界标准的「默认值 + 记住用户修改」偏好持久化:单一真相源,typed,
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
import 'blind_listen_settings.dart';
import 'intensive_listen_settings.dart' show PauseMode, ShadowingControlMode;

/// 全文盲听用户偏好覆盖(不可变,全字段可空)。
///
/// 字段对应 [BlindListenSettings] 的可改项;`null` = 用默认值。
class BlindListenPrefs {
  /// 播放速度覆盖(`null`=用智能默认,见 [resolve])。
  final double? playbackSpeed;

  /// 停顿模式覆盖(`null`=multiplier)。
  final PauseMode? pauseMode;

  /// 固定间隔秒数覆盖(`null`=10)。
  final int? fixedPauseSeconds;

  /// 段长倍数覆盖(`null`=0.5)。
  final double? pauseMultiplier;

  /// 控制模式覆盖(`null`=auto)。
  final ShadowingControlMode? controlMode;

  /// 每段循环次数覆盖(`null`=1)。
  final int? repeatCount;

  /// 目标段落时长秒数覆盖(旁路键,`null`=用智能默认 smartSeconds)。
  ///
  /// 非 BlindListenSettings 字段(仅决定分段),合法档位校验在屏幕层。
  final int? targetSeconds;

  const BlindListenPrefs({
    this.playbackSpeed,
    this.pauseMode,
    this.fixedPauseSeconds,
    this.pauseMultiplier,
    this.controlMode,
    this.repeatCount,
    this.targetSeconds,
  });

  /// 空偏好(用户未改动任何字段)。
  const BlindListenPrefs.empty()
    : playbackSpeed = null,
      pauseMode = null,
      fixedPauseSeconds = null,
      pauseMultiplier = null,
      controlMode = null,
      repeatCount = null,
      targetSeconds = null;

  /// 把偏好叠加到默认值,得到本次会话生效的完整 [BlindListenSettings]。
  ///
  /// [smartSpeed] 为按当前难度/阶段算出的动态默认速度;偏好未设速度时用它。
  /// 其余字段未设时回退各自静态默认(multiplier/10/0.5/auto/1)。
  BlindListenSettings resolve({required double smartSpeed}) =>
      BlindListenSettings(
        playbackSpeed: playbackSpeed ?? smartSpeed,
        pauseMode: pauseMode ?? PauseMode.multiplier,
        fixedPauseSeconds: fixedPauseSeconds ?? 10,
        pauseMultiplier: pauseMultiplier ?? 0.5,
        controlMode: controlMode ?? ShadowingControlMode.auto,
        repeatCount: repeatCount ?? 1,
      );

  /// 返回叠加 [other] 非空字段后的新偏好(用于细粒度 setter:只改传入的字段)。
  ///
  /// 注意:仅覆盖传入的**非空**字段,无法把某字段重置回 `null`——本 app
  /// 无「清除偏好」入口,用户只会从默认改成具体值或在具体值间切换。
  BlindListenPrefs copyWith({
    double? playbackSpeed,
    PauseMode? pauseMode,
    int? fixedPauseSeconds,
    double? pauseMultiplier,
    ShadowingControlMode? controlMode,
    int? repeatCount,
    int? targetSeconds,
  }) => BlindListenPrefs(
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    pauseMode: pauseMode ?? this.pauseMode,
    fixedPauseSeconds: fixedPauseSeconds ?? this.fixedPauseSeconds,
    pauseMultiplier: pauseMultiplier ?? this.pauseMultiplier,
    controlMode: controlMode ?? this.controlMode,
    repeatCount: repeatCount ?? this.repeatCount,
    targetSeconds: targetSeconds ?? this.targetSeconds,
  );

  /// 序列化为稀疏 JSON(只写非空字段:缺省即「用默认」)。
  Map<String, dynamic> toJson() => {
    if (playbackSpeed != null) 'playbackSpeed': playbackSpeed,
    if (pauseMode != null) 'pauseMode': pauseMode!.name,
    if (fixedPauseSeconds != null) 'fixedPauseSeconds': fixedPauseSeconds,
    if (pauseMultiplier != null) 'pauseMultiplier': pauseMultiplier,
    if (controlMode != null) 'controlMode': controlMode!.name,
    if (repeatCount != null) 'repeatCount': repeatCount,
    if (targetSeconds != null) 'targetSeconds': targetSeconds,
  };

  /// 防御性解析:字段缺失/类型错/越档一律视作未设(`null`),回退各自默认。
  factory BlindListenPrefs.fromJson(Map<String, dynamic> json) =>
      BlindListenPrefs(
        playbackSpeed: _parseSpeed(json['playbackSpeed']),
        pauseMode: _parsePauseMode(json['pauseMode']),
        fixedPauseSeconds: _parseFixedPauseSeconds(json['fixedPauseSeconds']),
        pauseMultiplier: _parsePauseMultiplier(json['pauseMultiplier']),
        controlMode: _parseControlMode(json['controlMode']),
        repeatCount: _parseRepeatCount(json['repeatCount']),
        targetSeconds: json['targetSeconds'] is int
            ? json['targetSeconds'] as int
            : null,
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
      (raw is int && BlindListenSettings.fixedPauseOptions.contains(raw))
      ? raw
      : null;

  /// 倍数:必须在可选档位内,否则未设。
  static double? _parsePauseMultiplier(dynamic raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return BlindListenSettings.multiplierOptions.contains(value) ? value : null;
  }

  /// 控制模式:合法枚举名才认,否则未设。
  static ShadowingControlMode? _parseControlMode(dynamic raw) => raw is String
      ? ShadowingControlMode.values.where((e) => e.name == raw).firstOrNull
      : null;

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
      other is BlindListenPrefs &&
          runtimeType == other.runtimeType &&
          playbackSpeed == other.playbackSpeed &&
          pauseMode == other.pauseMode &&
          fixedPauseSeconds == other.fixedPauseSeconds &&
          pauseMultiplier == other.pauseMultiplier &&
          controlMode == other.controlMode &&
          repeatCount == other.repeatCount &&
          targetSeconds == other.targetSeconds;

  @override
  int get hashCode => Object.hash(
    playbackSpeed,
    pauseMode,
    fixedPauseSeconds,
    pauseMultiplier,
    controlMode,
    repeatCount,
    targetSeconds,
  );
}
