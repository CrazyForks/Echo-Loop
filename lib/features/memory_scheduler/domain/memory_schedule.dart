/// 记忆调度当前快照领域模型。
library;

import 'dart:collection';

import 'memory_profile.dart';
import 'memory_subject_ref.dart';

/// 调度在算法流程中的阶段。
enum MemorySchedulePhase { newItem, learning, review, relearning }

/// 调度的业务生命周期状态。
enum MemoryScheduleStatus { active, archived }

/// 一个业务内容的当前记忆调度快照。
final class MemorySchedule {
  /// 创建调度快照，并将所有时间统一为 UTC。
  MemorySchedule({
    required String id,
    required this.subject,
    required this.profile,
    required String modelId,
    required this.modelStateVersion,
    required this.phase,
    required this.status,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? lastReviewedAt,
    required DateTime dueAt,
    required this.reviewCount,
    required this.lapseCount,
    required this.revision,
    required Map<String, Object?> modelState,
    required DateTime? archivedAt,
  }) : id = memoryRequiredText(id, 'id'),
       modelId = memoryRequiredText(modelId, 'modelId'),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       lastReviewedAt = lastReviewedAt?.toUtc(),
       dueAt = dueAt.toUtc(),
       modelState = UnmodifiableMapView<String, Object?>(modelState),
       archivedAt = archivedAt?.toUtc() {
    if (modelStateVersion <= 0 ||
        reviewCount < 0 ||
        lapseCount < 0 ||
        revision < 0) {
      throw ArgumentError('调度版本和计数不得为负，状态版本必须大于 0。');
    }
    if (lapseCount > reviewCount) {
      throw ArgumentError.value(lapseCount, 'lapseCount', '不能大于 reviewCount。');
    }
  }

  /// 调度记录 ID。
  final String id;

  /// 对应的业务主体。
  final MemorySubjectRef subject;

  /// 固定绑定的算法 Profile。
  final MemoryProfileRef profile;

  /// 产生当前状态的模型标识。
  final String modelId;

  /// adapter 状态序列化格式版本。
  final int modelStateVersion;

  /// 当前算法阶段。
  final MemorySchedulePhase phase;

  /// 生命周期状态。
  final MemoryScheduleStatus status;

  /// 首次创建时间。
  final DateTime createdAt;

  /// 最近一次快照更新时间。
  final DateTime updatedAt;

  /// 最近评分时间；新项为空。
  final DateTime? lastReviewedAt;

  /// 下一次到期绝对时间。
  final DateTime dueAt;

  /// 成功评分次数。
  final int reviewCount;

  /// 历史遗忘次数。
  final int lapseCount;

  /// 乐观锁版本。
  final int revision;

  /// adapter 私有、JSON 兼容的状态。
  final Map<String, Object?> modelState;

  /// 归档时间；活跃项为空。
  final DateTime? archivedAt;
}
