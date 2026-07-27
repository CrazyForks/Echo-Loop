/// 不可变算法 adapter 注册表。
library;

import '../domain/memory_model_adapter.dart';
import '../domain/memory_scheduler_exceptions.dart';
import '../domain/memory_subject_ref.dart';

/// 按稳定模型标识查找算法 adapter 的端口。
abstract interface class MemoryModelRegistry {
  /// 返回已注册 adapter；未知模型必须显式失败。
  MemoryModelAdapter get(String modelId);
}

/// 基于代码定义的不可变 adapter 注册表。
final class StaticMemoryModelRegistry implements MemoryModelRegistry {
  /// 创建注册表并拒绝重复 modelId。
  StaticMemoryModelRegistry(Iterable<MemoryModelAdapter> adapters)
    : _adapters = _index(adapters);

  final Map<String, MemoryModelAdapter> _adapters;

  @override
  MemoryModelAdapter get(String modelId) {
    final normalized = memoryRequiredText(modelId, 'modelId');
    final adapter = _adapters[normalized];
    if (adapter == null) {
      throw MemoryModelNotFoundException('未知记忆模型: $normalized');
    }
    return adapter;
  }

  static Map<String, MemoryModelAdapter> _index(
    Iterable<MemoryModelAdapter> adapters,
  ) {
    final result = <String, MemoryModelAdapter>{};
    for (final adapter in adapters) {
      final modelId = memoryRequiredText(adapter.modelId, 'adapter.modelId');
      if (result.containsKey(modelId)) {
        throw ArgumentError.value(modelId, 'adapters', 'modelId 重复。');
      }
      result[modelId] = adapter;
    }
    return Map.unmodifiable(result);
  }
}
