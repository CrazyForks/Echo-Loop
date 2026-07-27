/// 记忆算法 adapter 的应用自有端口。
library;

import 'dart:collection';

import 'memory_profile.dart';
import 'memory_rating.dart';
import 'memory_schedule.dart';

/// adapter 可持久化的私有模型状态。
final class MemoryModelState {
  /// 创建并冻结模型状态。
  MemoryModelState({
    required this.version,
    required Map<String, Object?> values,
  }) : values = UnmodifiableMapView<String, Object?>(values) {
    if (version <= 0) {
      throw ArgumentError.value(version, 'version', '必须大于 0。');
    }
  }

  final int version;
  final Map<String, Object?> values;
}

/// 一个评分分支的模型预览。
final class MemoryModelPreview {
  /// 创建模型预览。
  MemoryModelPreview({
    required this.state,
    required this.phase,
    required DateTime dueAt,
    required DateTime lastReviewedAt,
  }) : dueAt = dueAt.toUtc(),
       lastReviewedAt = lastReviewedAt.toUtc();

  final MemoryModelState state;
  final MemorySchedulePhase phase;
  final DateTime dueAt;
  final DateTime lastReviewedAt;
}

/// 四种评分的模型预览集合。
final class MemoryModelPreviewSet {
  /// 创建完整模型预览集合。
  const MemoryModelPreviewSet({
    required this.again,
    required this.hard,
    required this.good,
    required this.easy,
  });

  final MemoryModelPreview again;
  final MemoryModelPreview hard;
  final MemoryModelPreview good;
  final MemoryModelPreview easy;
}

/// 一次实际评分后的模型状态转换。
final class MemoryModelTransition {
  /// 创建模型状态转换。
  MemoryModelTransition({
    required this.state,
    required this.phase,
    required DateTime dueAt,
    required DateTime lastReviewedAt,
  }) : dueAt = dueAt.toUtc(),
       lastReviewedAt = lastReviewedAt.toUtc();

  final MemoryModelState state;
  final MemorySchedulePhase phase;
  final DateTime dueAt;
  final DateTime lastReviewedAt;
}

/// 隔离具体算法库的稳定应用端口。
abstract interface class MemoryModelAdapter {
  /// adapter 的稳定模型标识。
  String get modelId;

  /// 可读取的模型状态编码版本。
  Set<int> get supportedStateVersions;

  /// 校验该 adapter 能否执行 Profile。
  void validateProfile(MemoryProfile profile);

  /// 根据 Profile 和创建时间构造初始状态。
  MemoryModelState createInitialState({
    required MemoryProfile profile,
    required DateTime createdAt,
  });

  /// 无副作用地预览四种评分结果。
  MemoryModelPreviewSet preview({
    required MemoryProfile profile,
    required MemoryModelState current,
    required DateTime reviewedAt,
  });

  /// 提交一种评分后的纯状态转换。
  MemoryModelTransition review({
    required MemoryProfile profile,
    required MemoryModelState current,
    required MemoryRating rating,
    required DateTime reviewedAt,
  });
}
