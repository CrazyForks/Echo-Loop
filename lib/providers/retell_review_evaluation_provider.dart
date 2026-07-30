/// 复述 AI 评测的页面生命周期状态。
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_io/io.dart';

import '../config/api_config.dart';
import '../models/retell_review_evaluation.dart';
import '../services/app_logger.dart';
import '../services/retell_review_audio_preparer.dart';
import '../services/sentence_ai_api_client.dart';

const _maxReviewAudioBytes = 2 * 1024 * 1024;

/// 评测请求阶段。
enum RetellReviewEvaluationPhase { idle, loading, streaming, completed, failed }

/// 当前录音 attempt 对应的评测 UI 状态。
class RetellReviewEvaluationState {
  final String? attemptKey;
  final RetellReviewEvaluationPhase phase;
  final RetellReviewEvaluation? evaluation;
  final String? errorCode;

  const RetellReviewEvaluationState({
    this.attemptKey,
    this.phase = RetellReviewEvaluationPhase.idle,
    this.evaluation,
    this.errorCode,
  });

  bool get hasCachedResult =>
      phase == RetellReviewEvaluationPhase.completed && evaluation != null;
}

/// 评测端超出上传上限时的本地 fail-fast 异常。
class RetellReviewAudioTooLargeException implements Exception {
  const RetellReviewAudioTooLargeException();
}

/// 临时音频准备服务的注入点。
final retellReviewAudioPreparerProvider = Provider<RetellReviewAudioPreparer>(
  (_) => FfmpegRetellReviewAudioPreparer(),
);

/// 复述 AI 评测 controller。
///
/// 结果只缓存到当前录音 attempt；录音 badge 消失或换成新文件时，旧请求与旧数据
/// 必须立刻失效，避免异步回调把上一段结果写到下一段。
final retellReviewEvaluationProvider =
    NotifierProvider<
      RetellReviewEvaluationController,
      RetellReviewEvaluationState
    >(RetellReviewEvaluationController.new);

class RetellReviewEvaluationController
    extends Notifier<RetellReviewEvaluationState> {
  CancelToken? _cancelToken;
  var _generation = 0;

  @override
  RetellReviewEvaluationState build() {
    ref.onDispose(_cancelActiveRequest);
    return const RetellReviewEvaluationState();
  }

  /// 同步 badge 当前绑定的 attempt；传 null 表示 badge 生命周期已结束。
  void syncAttempt(String? attemptKey) {
    if (state.attemptKey == attemptKey) return;
    _generation += 1;
    _cancelActiveRequest();
    state = RetellReviewEvaluationState(attemptKey: attemptKey);
  }

  /// 拉取当前录音的评测。完整结果由同一 attempt 生命周期内的后续点击复用。
  Future<void> evaluate({
    required String attemptKey,
    required String recordingPath,
    required String originalText,
    required String targetLanguage,
  }) async {
    if (state.attemptKey != attemptKey) syncAttempt(attemptKey);
    if (state.hasCachedResult ||
        state.phase == RetellReviewEvaluationPhase.loading ||
        state.phase == RetellReviewEvaluationPhase.streaming) {
      return;
    }

    final generation = ++_generation;
    _cancelActiveRequest();
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    state = RetellReviewEvaluationState(
      attemptKey: attemptKey,
      phase: RetellReviewEvaluationPhase.loading,
    );

    File? preparedFile;
    try {
      final source = File(recordingPath);
      preparedFile = await ref
          .read(retellReviewAudioPreparerProvider)
          .prepare(source);
      if (!_isCurrent(generation, attemptKey)) return;
      if (await preparedFile.length() > _maxReviewAudioBytes) {
        throw const RetellReviewAudioTooLargeException();
      }

      var receivedFinalFrame = false;
      await for (final frame
          in ref
              .read(sentenceAiApiClientProvider)
              .evaluateReviewStream(
                audioFile: preparedFile,
                originalText: originalText,
                targetLanguage: targetLanguage,
                cancelToken: cancelToken,
              )) {
        if (!_isCurrent(generation, attemptKey)) return;
        state = RetellReviewEvaluationState(
          attemptKey: attemptKey,
          phase: frame.isFinal
              ? RetellReviewEvaluationPhase.completed
              : RetellReviewEvaluationPhase.streaming,
          evaluation: frame.evaluation,
        );
        receivedFinalFrame = frame.isFinal;
      }
      if (!receivedFinalFrame && _isCurrent(generation, attemptKey)) {
        throw const RetellReviewStreamException();
      }
    } on RetellReviewAudioPreparationException {
      _setFailure(generation, attemptKey, 'audio_preparation_failed');
    } on RetellReviewAudioTooLargeException {
      _setFailure(generation, attemptKey, 'audio_too_large');
    } on RetellReviewStreamException {
      _setFailure(generation, attemptKey, 'stream_failed');
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error)) {
        _setFailure(generation, attemptKey, 'request_failed');
      }
    } catch (error, stackTrace) {
      AppLogger.log(
        'RetellReview',
        '评测失败: error=$error stack=$stackTrace baseUrl=$apiBaseUrl',
      );
      _setFailure(generation, attemptKey, 'request_failed');
    } finally {
      if (preparedFile != null) {
        try {
          if (await preparedFile.exists()) await preparedFile.delete();
        } catch (error) {
          AppLogger.log('RetellReview', '临时评测音频清理失败: $error');
        }
      }
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  bool _isCurrent(int generation, String attemptKey) =>
      generation == _generation && state.attemptKey == attemptKey;

  void _setFailure(int generation, String attemptKey, String errorCode) {
    if (!_isCurrent(generation, attemptKey)) return;
    state = RetellReviewEvaluationState(
      attemptKey: attemptKey,
      phase: RetellReviewEvaluationPhase.failed,
      errorCode: errorCode,
    );
  }

  void _cancelActiveRequest() {
    _cancelToken?.cancel('retell review attempt invalidated');
    _cancelToken = null;
  }
}
