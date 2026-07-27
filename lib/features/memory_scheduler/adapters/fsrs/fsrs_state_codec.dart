/// FSRS Card 与应用自有模型状态之间的严格编解码。
library;

import 'package:fsrs/fsrs.dart' as fsrs;

import '../../domain/memory_model_adapter.dart';
import '../../domain/memory_scheduler_exceptions.dart';

/// FSRS adapter 当前持久化状态格式的版本。
const int kFsrsStateVersion = 1;

/// 负责把 FSRS Card 显式转换为应用拥有的状态结构。
final class FsrsStateCodec {
  /// 将第三方 Card 编码为稳定、JSON 兼容的应用状态。
  MemoryModelState encode(fsrs.Card card) => MemoryModelState(
    version: kFsrsStateVersion,
    values: <String, Object?>{
      'cardId': card.cardId,
      'state': card.state.value,
      'step': card.step,
      'stability': card.stability,
      'difficulty': card.difficulty,
      'due': card.due.toUtc().toIso8601String(),
      'lastReview': card.lastReview?.toUtc().toIso8601String(),
    },
  );

  /// 从应用状态恢复 Card；任何缺失或非法字段都显式失败。
  fsrs.Card decode(MemoryModelState state) {
    if (state.version != kFsrsStateVersion) {
      throw MemoryModelStateUnsupportedException(
        '不支持的 FSRS 状态版本: ${state.version}',
      );
    }
    final values = state.values;
    final cardId = _requiredInt(values, 'cardId');
    if (cardId < 0) {
      throw MemoryModelStateCorruptedException('FSRS cardId 不得为负。');
    }
    final rawState = _requiredInt(values, 'state');
    final step = _optionalInt(values, 'step');
    final stability = _optionalFiniteDouble(values, 'stability');
    final difficulty = _optionalFiniteDouble(values, 'difficulty');
    final due = _requiredUtcDateTime(values, 'due');
    final lastReview = _optionalUtcDateTime(values, 'lastReview');
    final fsrsState = _decodeState(rawState);

    if (fsrsState == fsrs.State.review && step != null) {
      throw MemoryModelStateCorruptedException('FSRS review 状态的 step 必须为空。');
    }
    if (fsrsState != fsrs.State.review && (step == null || step < 0)) {
      throw MemoryModelStateCorruptedException('FSRS 学习状态需要非负 step。');
    }
    if ((stability == null) != (difficulty == null)) {
      throw MemoryModelStateCorruptedException(
        'FSRS stability 与 difficulty 必须同时为空或同时存在。',
      );
    }
    return fsrs.Card(
      cardId: cardId,
      state: fsrsState,
      step: step,
      stability: stability,
      difficulty: difficulty,
      due: due,
      lastReview: lastReview,
    );
  }
}

fsrs.State _decodeState(int value) {
  try {
    return fsrs.State.fromValue(value);
  } on ArgumentError {
    throw MemoryModelStateCorruptedException('未知 FSRS state: $value');
  }
}

int _requiredInt(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is int) return value;
  throw MemoryModelStateCorruptedException('FSRS 状态字段 $key 必须是 int。');
}

int? _optionalInt(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value == null) return null;
  if (value is int) return value;
  throw MemoryModelStateCorruptedException('FSRS 状态字段 $key 必须是 int 或 null。');
}

double? _optionalFiniteDouble(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw MemoryModelStateCorruptedException('FSRS 状态字段 $key 必须是有限数值或 null。');
}

DateTime _requiredUtcDateTime(Map<String, Object?> values, String key) {
  final dateTime = _optionalUtcDateTime(values, key);
  if (dateTime == null) {
    throw MemoryModelStateCorruptedException('FSRS 状态字段 $key 不得为空。');
  }
  return dateTime;
}

DateTime? _optionalUtcDateTime(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value == null) return null;
  if (value is! String) {
    throw MemoryModelStateCorruptedException(
      'FSRS 状态字段 $key 必须是 ISO-8601 字符串。',
    );
  }
  final dateTime = DateTime.tryParse(value);
  if (dateTime == null || !dateTime.isUtc) {
    throw MemoryModelStateCorruptedException('FSRS 状态字段 $key 必须是 UTC 时间。');
  }
  return dateTime;
}
