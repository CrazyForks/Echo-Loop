/// 不可变 Profile 注册表。
library;

import '../domain/memory_profile.dart';
import '../domain/memory_scheduler_exceptions.dart';
import '../domain/memory_subject_ref.dart';

/// 按不可变引用查找 Profile，并提供新项默认 Profile 的端口。
abstract interface class MemoryProfileRegistry {
  /// 返回已发布 Profile；未知引用必须显式失败。
  MemoryProfile get(MemoryProfileRef ref);

  /// 返回指定内容域创建新调度时的默认 Profile。
  MemoryProfileRef defaultForNamespace(String namespace);
}

/// 基于代码定义的不可变 Profile 注册表。
final class StaticMemoryProfileRegistry implements MemoryProfileRegistry {
  /// 创建注册表并拒绝重复 Profile 或无效默认映射。
  StaticMemoryProfileRegistry({
    required Iterable<MemoryProfile> profiles,
    required Map<String, MemoryProfileRef> defaultsByNamespace,
  }) : this._(
         profiles: List<MemoryProfile>.unmodifiable(profiles),
         defaultsByNamespace: defaultsByNamespace,
       );

  StaticMemoryProfileRegistry._({
    required List<MemoryProfile> profiles,
    required Map<String, MemoryProfileRef> defaultsByNamespace,
  }) : _profiles = _indexProfiles(profiles),
       _defaultsByNamespace = _validateDefaults(profiles, defaultsByNamespace);

  final Map<MemoryProfileRef, MemoryProfile> _profiles;
  final Map<String, MemoryProfileRef> _defaultsByNamespace;

  @override
  MemoryProfile get(MemoryProfileRef ref) {
    final profile = _profiles[ref];
    if (profile == null) {
      throw MemoryProfileNotFoundException('未知 Profile: $ref');
    }
    return profile;
  }

  @override
  MemoryProfileRef defaultForNamespace(String namespace) {
    final normalized = memoryRequiredText(namespace, 'namespace');
    final ref = _defaultsByNamespace[normalized] ?? _defaultsByNamespace['*'];
    if (ref == null) {
      throw MemoryProfileNotFoundException(
        '未配置 namespace 默认 Profile: $normalized',
      );
    }
    return ref;
  }

  static Map<MemoryProfileRef, MemoryProfile> _indexProfiles(
    Iterable<MemoryProfile> profiles,
  ) {
    final result = <MemoryProfileRef, MemoryProfile>{};
    for (final profile in profiles) {
      if (result.containsKey(profile.ref)) {
        throw ArgumentError.value(profile.ref, 'profiles', 'Profile 引用重复。');
      }
      result[profile.ref] = profile;
    }
    if (result.isEmpty) {
      throw ArgumentError.value(profiles, 'profiles', '至少需要一个 Profile。');
    }
    return Map.unmodifiable(result);
  }

  static Map<String, MemoryProfileRef> _validateDefaults(
    Iterable<MemoryProfile> profiles,
    Map<String, MemoryProfileRef> defaults,
  ) {
    final profileRefs = profiles.map((profile) => profile.ref).toSet();
    final result = <String, MemoryProfileRef>{};
    for (final entry in defaults.entries) {
      final namespace = entry.key == '*'
          ? '*'
          : memoryRequiredText(entry.key, 'namespace');
      if (!profileRefs.contains(entry.value)) {
        throw ArgumentError.value(
          entry.value,
          'defaultsByNamespace',
          '默认 Profile 未注册。',
        );
      }
      result[namespace] = entry.value;
    }
    return Map.unmodifiable(result);
  }
}
