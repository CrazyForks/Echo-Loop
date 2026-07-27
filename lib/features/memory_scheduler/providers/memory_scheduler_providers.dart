/// 通用记忆调度基础设施的 Riverpod 依赖装配。
library;

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../database/providers.dart';
import '../adapters/fsrs/fsrs_memory_model_adapter.dart';
import '../application/default_memory_scheduler.dart';
import '../application/memory_model_registry.dart';
import '../application/memory_profile_registry.dart';
import '../application/memory_schedule_repository.dart';
import '../application/memory_scheduler.dart';
import '../config/memory_profiles.dart';
import '../data/drift_memory_schedule_repository.dart';

/// 生产环境 UUID 生成器。
final class UuidMemoryIdGenerator implements MemoryIdGenerator {
  /// 创建 UUID v4 生成器。
  UuidMemoryIdGenerator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  String newId() => _uuid.v4();
}

/// 已发布 Profile 的只读注册表。
final memoryProfileRegistryProvider = Provider<MemoryProfileRegistry>((ref) {
  return kMemoryProfileRegistry;
});

/// 已注册算法 adapter 的只读注册表。
final memoryModelRegistryProvider = Provider<MemoryModelRegistry>((ref) {
  return StaticMemoryModelRegistry(<FsrsMemoryModelAdapter>[
    FsrsMemoryModelAdapter(),
  ]);
});

/// 调度快照和事件的 Drift Repository。
final memoryScheduleRepositoryProvider = Provider<MemoryScheduleRepository>((
  ref,
) {
  return DriftMemoryScheduleRepository(ref.watch(appDatabaseProvider));
});

/// 调度 ID 的生产生成器。
final memoryIdGeneratorProvider = Provider<MemoryIdGenerator>((ref) {
  return UuidMemoryIdGenerator();
});

/// 默认调度 facade；不缓存任何调度状态。
final memorySchedulerProvider = Provider<MemoryScheduler>((ref) {
  return DefaultMemoryScheduler(
    repository: ref.watch(memoryScheduleRepositoryProvider),
    profileRegistry: ref.watch(memoryProfileRegistryProvider),
    modelRegistry: ref.watch(memoryModelRegistryProvider),
    idGenerator: ref.watch(memoryIdGeneratorProvider),
    clock: const Clock(),
  );
});
