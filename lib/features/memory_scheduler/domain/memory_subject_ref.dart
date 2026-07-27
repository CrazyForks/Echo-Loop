/// 记忆调度的业务主体标识。
library;

/// 标识一个内容域内可被调度的稳定业务主体。
final class MemorySubjectRef {
  /// 创建业务主体标识，并移除两端空白。
  MemorySubjectRef({required String namespace, required String subjectId})
    : namespace = _requiredText(namespace, 'namespace'),
      subjectId = _requiredText(subjectId, 'subjectId');

  /// 业务内容域，例如未来的 `favorite_sentence`。
  final String namespace;

  /// 该内容域中的稳定业务标识。
  final String subjectId;

  @override
  bool operator ==(Object other) =>
      other is MemorySubjectRef &&
      namespace == other.namespace &&
      subjectId == other.subjectId;

  @override
  int get hashCode => Object.hash(namespace, subjectId);

  @override
  String toString() => 'MemorySubjectRef($namespace, $subjectId)';
}

/// 验证标识文本并返回规范化后的值。
String memoryRequiredText(String value, String fieldName) =>
    _requiredText(value, fieldName);

String _requiredText(String value, String fieldName) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, fieldName, '不能为空。');
  }
  return normalized;
}
