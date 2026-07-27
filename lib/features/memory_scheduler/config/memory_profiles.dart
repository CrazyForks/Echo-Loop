/// 内置且冻结的记忆调度 Profile 配置。
library;

import '../application/memory_profile_registry.dart';
import '../domain/memory_profile.dart';

/// 默认 FSRS Profile 的稳定引用。
final MemoryProfileRef kFsrsDefaultProfileRef = MemoryProfileRef(
  profileId: 'fsrs.default',
  profileVersion: 1,
);

/// `fsrs.default@1` 的冻结配置；adapter 会在任务 2 严格校验每项参数。
final MemoryProfile kFsrsDefaultProfile = MemoryProfile(
  ref: kFsrsDefaultProfileRef,
  modelId: 'fsrs',
  parameters: <String, Object?>{
    'weights': <double>[
      0.2172,
      1.1771,
      3.2602,
      16.1507,
      7.0114,
      0.57,
      2.0966,
      0.0069,
      1.5261,
      0.112,
      1.0178,
      1.849,
      0.1133,
      0.3127,
      2.2934,
      0.2191,
      3.0004,
      0.7536,
      0.3332,
      0.1437,
      0.2,
    ],
    'desiredRetention': 0.9,
    'learningStepsSeconds': <int>[60, 600],
    'relearningStepsSeconds': <int>[600],
    'maximumIntervalDays': 36500,
  },
  enableFuzzing: false,
);

/// 内置 Profile 注册表；所有 namespace 的新项默认使用该版本。
final MemoryProfileRegistry kMemoryProfileRegistry =
    StaticMemoryProfileRegistry(
      profiles: <MemoryProfile>[kFsrsDefaultProfile],
      defaultsByNamespace: <String, MemoryProfileRef>{
        '*': kFsrsDefaultProfileRef,
      },
    );
