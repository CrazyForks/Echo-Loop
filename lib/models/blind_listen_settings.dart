/// 盲听设置模型
///
/// 控制盲听段落播放的播放速度、重复次数和段间停顿模式。
/// 仅在会话内临时生效，不持久化。
library;

import 'intensive_listen_settings.dart' show PauseMode, ShadowingControlMode;
import '../utils/playback_speed.dart';

/// 盲听设置（会话内临时生效）
class BlindListenSettings {
  /// 每段重复次数（`0`=∞ 无限，`1-10/20/30/40/50`=有限次数，默认 1）
  final int repeatCount;

  /// 停顿模式（默认 multiplier）
  final PauseMode pauseMode;

  /// 固定间隔秒数（默认 10）
  final int fixedPauseSeconds;

  /// 段长倍数（默认 0.5）
  final double pauseMultiplier;

  /// 控制模式（默认 auto）
  final ShadowingControlMode controlMode;

  /// 播放速度（0.5x-2.0x，默认 1.0x）
  final double playbackSpeed;

  /// 是否为手动控制模式
  bool get isManualMode => controlMode == ShadowingControlMode.manual;

  /// 入口弹窗使用的离散速度选项
  ///
  /// 与其他练习入口共用统一档位，保证默认值都能命中。
  static const List<double> briefingPlaybackSpeedOptions =
      kUnifiedPlaybackSpeeds;

  /// 固定间隔可选值（秒）
  static const List<int> fixedPauseOptions = [5, 10, 15, 20, 25, 30, 45, 60];

  /// 倍数可选值
  static const List<double> multiplierOptions = [
    0.3,
    0.5,
    1.0,
    1.5,
    2.0,
    3.0,
    4.0,
    5.0,
  ];

  const BlindListenSettings({
    this.repeatCount = 1,
    this.pauseMode = PauseMode.multiplier,
    this.fixedPauseSeconds = 10,
    this.pauseMultiplier = 0.5,
    this.controlMode = ShadowingControlMode.auto,
    this.playbackSpeed = 1.0,
  });

  /// 从弹窗回调的 pauseMultiplier 创建设置
  ///
  /// -1.0 表示"自动"（智能模式），其他值为段长倍数模式。
  factory BlindListenSettings.fromMultiplier(double pauseMultiplier) {
    if (pauseMultiplier < 0) {
      return const BlindListenSettings(pauseMode: PauseMode.smart);
    }
    return BlindListenSettings(pauseMultiplier: pauseMultiplier);
  }

  /// 根据段落时长计算段间停顿时长
  ///
  /// 全模式统一 clamp 到 [3s, 30s]：
  /// - 自动模式: 0.5 × 段长
  /// - 固定模式: fixedPauseSeconds
  /// - 倍数模式: pauseMultiplier × 段长
  Duration calculatePauseDuration(Duration paragraphDuration) {
    final ms = switch (pauseMode) {
      PauseMode.smart => (paragraphDuration.inMilliseconds * 0.5).round(),
      PauseMode.fixed => fixedPauseSeconds * 1000,
      PauseMode.multiplier =>
        (paragraphDuration.inMilliseconds * pauseMultiplier).round(),
    };
    return Duration(milliseconds: ms.clamp(3000, 30000));
  }

  BlindListenSettings copyWith({
    int? repeatCount,
    PauseMode? pauseMode,
    int? fixedPauseSeconds,
    double? pauseMultiplier,
    ShadowingControlMode? controlMode,
    double? playbackSpeed,
  }) {
    return BlindListenSettings(
      repeatCount: repeatCount ?? this.repeatCount,
      pauseMode: pauseMode ?? this.pauseMode,
      fixedPauseSeconds: fixedPauseSeconds ?? this.fixedPauseSeconds,
      pauseMultiplier: pauseMultiplier ?? this.pauseMultiplier,
      controlMode: controlMode ?? this.controlMode,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  /// 防御性解析：`0`=∞；有限次数上限为 50；其余非法值回退默认。
  factory BlindListenSettings.fromJson(Map<String, dynamic> json) {
    return BlindListenSettings(
      repeatCount: _parseRepeatCount(json['repeatCount']),
      pauseMode: _parsePauseMode(json['pauseMode']),
      fixedPauseSeconds: _parseFixedPause(json['fixedPauseSeconds']),
      pauseMultiplier: _parseMultiplier(json['pauseMultiplier']),
      controlMode: _parseControlMode(json['controlMode']),
      playbackSpeed: _parsePlaybackSpeed(json['playbackSpeed']),
    );
  }

  Map<String, dynamic> toJson() => {
    'repeatCount': repeatCount,
    'pauseMode': pauseMode.name,
    'fixedPauseSeconds': fixedPauseSeconds,
    'pauseMultiplier': pauseMultiplier,
    'controlMode': controlMode.name,
    'playbackSpeed': playbackSpeed,
  };

  static int _parseRepeatCount(dynamic raw) {
    if (raw is! int) return 1;
    if (raw == 0) return 0;
    if (raw < 1) return 1;
    return raw > 50 ? 50 : raw;
  }

  static PauseMode _parsePauseMode(dynamic raw) {
    if (raw is! String) return PauseMode.multiplier;
    return PauseMode.values.where((e) => e.name == raw).firstOrNull ??
        PauseMode.multiplier;
  }

  static int _parseFixedPause(dynamic raw) {
    if (raw is! int) return 10;
    if (!fixedPauseOptions.contains(raw)) return 10;
    return raw;
  }

  static double _parseMultiplier(dynamic raw) {
    if (raw is! num) return 0.5;
    final value = raw.toDouble();
    if (!multiplierOptions.contains(value)) return 0.5;
    return value;
  }

  static ShadowingControlMode _parseControlMode(dynamic raw) {
    if (raw is! String) return ShadowingControlMode.auto;
    return ShadowingControlMode.values
            .where((e) => e.name == raw)
            .firstOrNull ??
        ShadowingControlMode.auto;
  }

  static double _parsePlaybackSpeed(dynamic raw) {
    if (raw is! num) return 1.0;
    return normalizePlaybackSpeed(raw.toDouble());
  }
}
