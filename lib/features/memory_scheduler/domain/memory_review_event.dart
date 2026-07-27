/// 记忆调度的只追加评分事件模型。
library;

import 'memory_profile.dart';
import 'memory_rating.dart';
import 'memory_subject_ref.dart';

/// 一次已提交评分的模型无关审计事实。
final class MemoryReviewEvent {
  /// 创建评分事件，并将时间统一为 UTC。
  MemoryReviewEvent({
    required String id,
    required String scheduleId,
    required this.sequence,
    required String operationId,
    required this.rating,
    required this.isLapse,
    required DateTime reviewedAt,
    required this.responseTime,
    required this.profile,
    required String modelId,
    required this.modelStateVersion,
    required DateTime dueBefore,
    required DateTime dueAfter,
    required this.scheduleRevisionAfter,
    required DateTime createdAt,
  }) : id = memoryRequiredText(id, 'id'),
       scheduleId = memoryRequiredText(scheduleId, 'scheduleId'),
       operationId = memoryRequiredText(operationId, 'operationId'),
       modelId = memoryRequiredText(modelId, 'modelId'),
       reviewedAt = reviewedAt.toUtc(),
       dueBefore = dueBefore.toUtc(),
       dueAfter = dueAfter.toUtc(),
       createdAt = createdAt.toUtc() {
    if (sequence <= 0 || modelStateVersion <= 0 || scheduleRevisionAfter <= 0) {
      throw ArgumentError('事件序号、状态版本和结果 revision 必须大于 0。');
    }
    if (responseTime != null && responseTime! < Duration.zero) {
      throw ArgumentError.value(responseTime, 'responseTime', '不得为负。');
    }
  }

  /// 事件 ID。
  final String id;

  /// 所属调度 ID。
  final String scheduleId;

  /// 同一调度内从 1 起连续递增的事件序号。
  final int sequence;

  /// 调用方提供的幂等键。
  final String operationId;

  /// 用户评分。
  final MemoryRating rating;

  /// 是否在 review 阶段评分 again。
  final bool isLapse;

  /// 评分发生时间。
  final DateTime reviewedAt;

  /// 可选作答耗时遥测。
  final Duration? responseTime;

  /// 评分时使用的 Profile。
  final MemoryProfileRef profile;

  /// 评分时使用的模型。
  final String modelId;

  /// 评分后状态的编码版本。
  final int modelStateVersion;

  /// 评分前到期时间。
  final DateTime dueBefore;

  /// 评分后到期时间。
  final DateTime dueAfter;

  /// 该事件提交后的调度 revision。
  final int scheduleRevisionAfter;

  /// 事件落库时间。
  final DateTime createdAt;
}
