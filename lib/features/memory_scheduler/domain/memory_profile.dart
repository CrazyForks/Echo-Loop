/// 记忆调度算法 Profile 的稳定定义。
library;

import 'dart:collection';

import 'memory_subject_ref.dart';

/// 标识一个不可变发布的算法 Profile 版本。
final class MemoryProfileRef {
  /// 创建 Profile 标识。
  MemoryProfileRef({required String profileId, required int profileVersion})
    : profileId = memoryRequiredText(profileId, 'profileId'),
      profileVersion = _positive(profileVersion, 'profileVersion');

  /// Profile 的逻辑名称。
  final String profileId;

  /// 不可原地修改的发布版本。
  final int profileVersion;

  @override
  bool operator ==(Object other) =>
      other is MemoryProfileRef &&
      profileId == other.profileId &&
      profileVersion == other.profileVersion;

  @override
  int get hashCode => Object.hash(profileId, profileVersion);

  @override
  String toString() => 'MemoryProfileRef($profileId@$profileVersion)';
}

/// 算法类型和冻结参数组成的不可变 Profile。
final class MemoryProfile {
  /// 创建并冻结 Profile 参数，避免发布后被外部集合修改。
  MemoryProfile({
    required this.ref,
    required String modelId,
    required Map<String, Object?> parameters,
    required this.enableFuzzing,
  }) : modelId = memoryRequiredText(modelId, 'modelId'),
       parameters = UnmodifiableMapView<String, Object?>(<String, Object?>{
         for (final entry in parameters.entries)
           entry.key: _freezeValue(entry.value),
       });

  /// Profile 的版本引用。
  final MemoryProfileRef ref;

  /// 算法 adapter 标识。
  final String modelId;

  /// 由 adapter 严格解释的 JSON 兼容参数快照。
  final Map<String, Object?> parameters;

  /// 是否允许算法引入随机扰动。
  final bool enableFuzzing;
}

int _positive(int value, String fieldName) {
  if (value <= 0) {
    throw ArgumentError.value(value, fieldName, '必须大于 0。');
  }
  return value;
}

Object? _freezeValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    return UnmodifiableMapView<Object?, Object?>(<Object?, Object?>{
      for (final entry in value.entries) entry.key: _freezeValue(entry.value),
    });
  }
  if (value is Iterable<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  return value;
}
