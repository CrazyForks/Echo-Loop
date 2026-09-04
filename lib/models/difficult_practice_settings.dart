/// 难句补练/收藏复习设置模型
///
/// 独立于播放状态的纯配置模型，控制难句补练和收藏复习的播放参数。
/// 复用 [PauseMode] 枚举和选项列表。
library;

import 'dart:math' as math;

import 'intensive_listen_settings.dart';
import '../utils/playback_speed.dart';

/// 难句补练/收藏复习设置
///
/// 包含控制模式、盲听循环次数、跟读循环次数和句间停顿配置。
/// 设置仅对当次练习有效，不持久化。
class DifficultPracticeSettings {
  /// 控制模式（默认 auto），复用跟读页已有枚举
  final ShadowingControlMode controlMode;

  /// 盲听循环次数（`0`=∞ 无限，`1-10/20/30/40/50`=有限次数，默认 1）
  final int blindListenRepeatCount;

  /// 跟读循环次数（`0`=∞ 无限，`1-10/20/30/40/50`=有限次数，默认 3）
  final int shadowReadingRepeatCount;

  /// 停顿模式（默认 smart）
  final PauseMode pauseMode;

  /// 固定间隔秒数（默认 3）
  final int fixedPauseSeconds;

  /// 句长倍数（默认 2.0）
  final double pauseMultiplier;

  /// 播放速度（0.5x-2.0x，默认 1.0x），难句补练和收藏复习共用。
  final double playbackSpeed;

  /// 入口弹窗使用的离散速度选项
  ///
  /// 与 [BlindListenSettings.briefingPlaybackSpeedOptions] / [RetellSettings.briefingPlaybackSpeedOptions] 保持一致。
  static const List<double> briefingPlaybackSpeedOptions =
      kUnifiedPlaybackSpeeds;

  const DifficultPracticeSettings({
    this.controlMode = ShadowingControlMode.auto,
    this.blindListenRepeatCount = 1,
    this.shadowReadingRepeatCount = 3,
    this.pauseMode = PauseMode.smart,
    this.fixedPauseSeconds = 3,
    this.pauseMultiplier = 2.0,
    this.playbackSpeed = 1.0,
  });

  /// 是否为手动控制模式
  bool get isManualMode => controlMode == ShadowingControlMode.manual;

  DifficultPracticeSettings copyWith({
    ShadowingControlMode? controlMode,
    int? blindListenRepeatCount,
    int? shadowReadingRepeatCount,
    PauseMode? pauseMode,
    int? fixedPauseSeconds,
    double? pauseMultiplier,
    double? playbackSpeed,
  }) {
    return DifficultPracticeSettings(
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
  }

  /// 计算句间停顿时长
  ///
  /// 根据 [pauseMode] 和句子时长计算停顿：
  /// - smart：clamp(1秒 + 0.6 × 句子时长, 2秒, 20秒)
  /// - fixed：固定秒数
  /// - multiplier：句长 × 倍数，至少 1000ms
  Duration calculateInterSentencePause(Duration sentenceDuration) {
    switch (pauseMode) {
      case PauseMode.smart:
        final ms = 1000 + (sentenceDuration.inMilliseconds * 0.6).round();
        return Duration(milliseconds: ms.clamp(2000, 20000));
      case PauseMode.fixed:
        return Duration(seconds: fixedPauseSeconds);
      case PauseMode.multiplier:
        final ms = (sentenceDuration.inMilliseconds * pauseMultiplier).round();
        return Duration(milliseconds: math.max(ms, 1000));
    }
  }

  Map<String, dynamic> toJson() => {
    'controlMode': controlMode.name,
    'blindListenRepeatCount': blindListenRepeatCount,
    'shadowReadingRepeatCount': shadowReadingRepeatCount,
    'pauseMode': pauseMode.name,
    'fixedPauseSeconds': fixedPauseSeconds,
    'pauseMultiplier': pauseMultiplier,
    'playbackSpeed': playbackSpeed,
  };

  /// 防御性解析：非法值回退默认
  factory DifficultPracticeSettings.fromJson(Map<String, dynamic> json) {
    return DifficultPracticeSettings(
      controlMode: _parseControlMode(json['controlMode']),
      blindListenRepeatCount: _clampInt(json['blindListenRepeatCount'], 1, 50),
      shadowReadingRepeatCount: _clampInt(
        json['shadowReadingRepeatCount'],
        1,
        50,
        fallback: 3,
      ),
      pauseMode: _parsePauseMode(json['pauseMode']),
      fixedPauseSeconds: _parseFixedPause(json['fixedPauseSeconds']),
      pauseMultiplier: _parseMultiplier(json['pauseMultiplier']),
      playbackSpeed: _parsePlaybackSpeed(json['playbackSpeed']),
    );
  }

  /// 解析播放速度：归一化到统一支持档位，否则回退 1.0
  static double _parsePlaybackSpeed(dynamic raw) {
    if (raw is! num) return 1.0;
    return normalizePlaybackSpeed(raw.toDouble());
  }

  static ShadowingControlMode _parseControlMode(dynamic raw) {
    if (raw is! String) return ShadowingControlMode.auto;
    return ShadowingControlMode.values
            .where((e) => e.name == raw)
            .firstOrNull ??
        ShadowingControlMode.auto;
  }

  static int _clampInt(dynamic raw, int min, int max, {int fallback = 1}) {
    if (raw is! int) return fallback;
    if (raw == 0) return 0;
    return raw.clamp(min, max);
  }

  static PauseMode _parsePauseMode(dynamic raw) {
    if (raw is! String) return PauseMode.smart;
    return PauseMode.values.where((e) => e.name == raw).firstOrNull ??
        PauseMode.smart;
  }

  static int _parseFixedPause(dynamic raw) {
    if (raw is! int) return 3;
    if (!IntensiveListenSettings.fixedPauseOptions.contains(raw)) return 3;
    return raw;
  }

  static double _parseMultiplier(dynamic raw) {
    if (raw is! num) return 2.0;
    final value = raw.toDouble();
    if (!IntensiveListenSettings.multiplierOptions.contains(value)) return 2.0;
    return value;
  }
}
