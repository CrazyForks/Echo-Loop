/// 记忆调度可识别异常类型。
library;

/// 记忆调度领域异常的公共基类。
sealed class MemorySchedulerException implements Exception {
  /// 创建领域异常。
  const MemorySchedulerException(this.message);

  /// 面向日志和调用方的稳定错误描述。
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class MemoryScheduleNotFoundException extends MemorySchedulerException {
  const MemoryScheduleNotFoundException(super.message);
}

final class MemoryScheduleArchivedException extends MemorySchedulerException {
  const MemoryScheduleArchivedException(super.message);
}

final class MemoryScheduleStatusException extends MemorySchedulerException {
  const MemoryScheduleStatusException(super.message);
}

final class MemoryScheduleConflictException extends MemorySchedulerException {
  const MemoryScheduleConflictException(super.message);
}

final class MemoryOperationIdConflictException
    extends MemorySchedulerException {
  const MemoryOperationIdConflictException(super.message);
}

final class MemoryIdempotencyReplayStaleException
    extends MemorySchedulerException {
  const MemoryIdempotencyReplayStaleException(super.message);
}

final class MemoryProfileNotFoundException extends MemorySchedulerException {
  const MemoryProfileNotFoundException(super.message);
}

final class MemoryModelNotFoundException extends MemorySchedulerException {
  const MemoryModelNotFoundException(super.message);
}

final class MemoryModelStateUnsupportedException
    extends MemorySchedulerException {
  const MemoryModelStateUnsupportedException(super.message);
}

final class MemoryModelStateCorruptedException
    extends MemorySchedulerException {
  const MemoryModelStateCorruptedException(super.message);
}

final class MemoryReviewTimeOrderException extends MemorySchedulerException {
  const MemoryReviewTimeOrderException(super.message);
}

final class MemoryReplayException extends MemorySchedulerException {
  const MemoryReplayException(super.message);
}

final class MemoryValidationException extends MemorySchedulerException {
  const MemoryValidationException(super.message);
}
