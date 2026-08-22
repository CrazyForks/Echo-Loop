/// 通用调度 Flashcard 的领域类型。
library;

import '../../memory_scheduler/domain/memory_rating.dart';
import '../../memory_scheduler/domain/memory_scheduler_results.dart';
import '../../memory_scheduler/domain/memory_subject_ref.dart';

/// 一张带调度 revision 的内容卡片。
final class ScheduledFlashcard<T> {
  /// 创建卡片。
  ScheduledFlashcard({
    required this.subject,
    required this.content,
    required this.scheduleRevision,
    required DateTime dueAt,
    this.status = ScheduledFlashcardStatus.pending,
    this.retryCount = 0,
  }) : dueAt = dueAt.toUtc();

  final MemorySubjectRef subject;
  final T content;
  int scheduleRevision;
  DateTime dueAt;
  ScheduledFlashcardStatus status;
  int retryCount;
}

/// 卡片在当前复习会话中的临时状态；不会持久化。
enum ScheduledFlashcardStatus { pending, retry }

/// 卡片会话的阶段。
enum ScheduledFlashcardPhase {
  loadingDeck,
  prompt,
  answer,
  submittingRating,
  completed,
}

/// 通用卡片队列来源。
abstract interface class FlashcardDeckSource<T> {
  /// 读取本次会话快照。
  Future<List<ScheduledFlashcard<T>>> load();
}

/// 调度评分边界，避免通用层依赖具体 scheduler 实现。
abstract interface class FlashcardRatingPort {
  /// 预览四档评分。
  Future<MemoryRatingPreviewSet> preview({
    required MemorySubjectRef subject,
    required int expectedRevision,
    required DateTime reviewedAt,
  });

  /// 提交一档评分。
  Future<MemoryReviewResult> submit({
    required MemorySubjectRef subject,
    required MemoryRating rating,
    required MemoryRatingPreview preview,
    required int expectedRevision,
    required Duration responseTime,
    required String operationId,
  });

  /// 在乐观锁冲突后读取当前 revision。
  Future<int> reloadRevision(MemorySubjectRef subject);
}
