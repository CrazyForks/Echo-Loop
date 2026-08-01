/// 语音练习评级 Badge（共享组件）
///
/// 融合评级文字 + 播放图标的可点击胶囊 Badge。
/// 跟读、复述、难句补练页面共用，各自控制外部布局位置。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/rating_thresholds.dart';
import '../../models/speech_practice_models.dart';
import '../../services/app_logger.dart';
import '../../services/audio_preview_controller.dart';
import 'tappable_wrapper.dart';

// 重导出 RatingThresholds，保持现有 import 兼容
export '../../models/rating_thresholds.dart';

/// 语音评级 Badge 的播放控制器。
///
/// 页面可通过它触发与用户点击 Badge 相同的播放/停止流程，
/// 例如复述评估完成后的自动回放需要同步 Badge 的停止图标状态。
class SpeechRatingBadgeController {
  _SpeechRatingBadgeState? _state;

  /// 当前 Badge 是否正在播放录音。
  bool get isPlaying => _state?._isPlaying ?? false;

  /// 当前是否已绑定到页面上的 Badge。
  bool get isAttached => _state != null;

  /// 当前绑定 Badge 的录音文件路径，用于页面级诊断日志。
  String? get attachedFilePath => _state?.widget.attempt.filePath;

  /// 当前绑定 Badge 的 promptId，用于页面级诊断日志。
  String? get attachedPromptId => _state?.widget.attempt.promptId;

  Future<void> play() async {
    final state = _state;
    if (state == null) {
      AppLogger.log('SpeechRatingBadge', 'controller.play 跳过: badge 未挂载');
      return;
    }
    await state._playFromController();
  }

  Future<void> stop() async {
    final state = _state;
    if (state == null) {
      AppLogger.log('SpeechRatingBadge', 'controller.stop 跳过: badge 未挂载');
      return;
    }
    await state._stopPlayback();
  }

  void _attach(_SpeechRatingBadgeState state) {
    _state = state;
    AppLogger.log(
      'SpeechRatingBadge',
      'controller attach: prompt=${state.widget.attempt.promptId}, '
          'path=${state.widget.attempt.filePath ?? "none"}',
    );
  }

  void _detach(_SpeechRatingBadgeState state) {
    if (_state == state) {
      AppLogger.log(
        'SpeechRatingBadge',
        'controller detach: prompt=${state.widget.attempt.promptId}, '
            'path=${state.widget.attempt.filePath ?? "none"}, '
            'playing=${state._isPlaying}',
      );
      _state = null;
    }
  }
}

/// 语音练习评级 Badge。
///
/// Badge 自己管理录音回放和图标切换：
/// - 未播放：喇叭图标
/// - 播放中：停止图标
///
/// 页面层只需通过 [onBeforePlayback] 在播放前执行必要的流程清理，
/// 例如取消倒计时、切到 WaitingForUser、暂停主音频等。
class SpeechRatingBadge extends StatefulWidget {
  final AppLocalizations l10n;
  final SpeechPracticeAttempt attempt;

  /// 播放前回调。
  ///
  /// 用于让调用方先清理页面级状态，再开始播放录音。
  final FutureOr<void> Function()? onBeforePlayback;

  /// 评分阈值，默认跟读阈值。
  final RatingThresholds thresholds;

  /// 试听控制器工厂。
  ///
  /// 默认自建一个，只服务这一个 Badge。需要与页面其他入口（如自动回放、
  /// 评估弹窗的播放按钮）共用同一份播放状态时，注入同一个 controller；
  /// 此时其生命周期归注入方，Badge 不会在自身 dispose 时释放它。
  final AudioPreviewController Function()? previewControllerFactory;

  /// 外部播放控制器，用于自动回放时复用 Badge 的播放状态和停止图标。
  final SpeechRatingBadgeController? controller;

  const SpeechRatingBadge({
    super.key,
    required this.l10n,
    required this.attempt,
    this.onBeforePlayback,
    this.thresholds = RatingThresholds.listenAndRepeat,
    this.previewControllerFactory,
    this.controller,
  });

  @override
  State<SpeechRatingBadge> createState() => _SpeechRatingBadgeState();
}

class _SpeechRatingBadgeState extends State<SpeechRatingBadge> {
  late final AudioPreviewController _preview;

  /// 自建的 controller 由 Badge 释放，注入的归注入方。
  late final bool _ownsPreview;

  /// 播放状态的唯一来源是 [_preview]，Badge 不另存一份。
  bool get _isPlaying => _preview.isPlaying;

  @override
  void initState() {
    super.initState();
    final injected = widget.previewControllerFactory?.call();
    _ownsPreview = injected == null;
    _preview = injected ?? AudioPreviewController();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant SpeechRatingBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    final oldPath = oldWidget.attempt.filePath;
    final newPath = widget.attempt.filePath;
    if (oldPath != newPath && _isPlaying) {
      unawaited(_stopPlayback());
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    if (_ownsPreview) unawaited(_preview.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attempt = widget.attempt;

    // 只有识别失败时，才退回显示「录音」胶囊。
    // 评估已完成但 transcript 为空时，仍然应该显示评级 badge。
    if (attempt.isRecognitionFailure && attempt.hasRecording) {
      return _buildRecordingOnlyBadge(theme);
    }

    // 识别失败但没有录音文件时，退回纯文字反馈。
    if (attempt.isRecognitionFailure) {
      return Text(
        _feedbackText(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: _statusColor(theme),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (!attempt.hasFinalFeedback) {
      return const SizedBox.shrink();
    }

    final style = _ratingStyle(theme);

    return TappableWrapper(
      onTap: attempt.hasRecording ? _handleTap : null,
      feedbackType: TapFeedback.opacity,
      pressedOpacity: 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [style.backgroundStart, style.backgroundEnd],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: style.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _ratingLabel(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: style.textColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            if (attempt.hasRecording) ...[
              const SizedBox(width: 6),
              _buildPlaybackIcon(style.textColor.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 播放/停止图标，直接跟随 service 的播放状态。
  ///
  /// 自动回放和用户手动点击共用同一个 service，所以两种来源的播放都会让图标切换，
  /// 不需要 Badge 自己同步状态。
  Widget _buildPlaybackIcon(Color color) => ValueListenableBuilder<bool>(
    valueListenable: _preview.isPlayingListenable,
    builder: (context, isPlaying, _) => Icon(
      isPlaying ? Icons.stop_rounded : Icons.volume_up_outlined,
      size: 16,
      color: color,
    ),
  );

  Future<void> _handleTap() async {
    if (_isPlaying) {
      await _stopPlayback();
      return;
    }

    await _playFromController();
  }

  Future<void> _playFromController() async {
    if (_isPlaying) {
      AppLogger.log(
        'SpeechRatingBadge',
        '播放跳过: 已在播放 path=${widget.attempt.filePath ?? "none"}',
      );
      return;
    }

    final filePath = widget.attempt.filePath;
    if (filePath == null || filePath.isEmpty) {
      AppLogger.log(
        'SpeechRatingBadge',
        '播放跳过: 无录音文件 prompt=${widget.attempt.promptId}',
      );
      return;
    }

    AppLogger.log(
      'SpeechRatingBadge',
      '准备播放录音: prompt=${widget.attempt.promptId}, path=$filePath',
    );
    await widget.onBeforePlayback?.call();
    if (!mounted) return;

    // 失败与被打断都不算播完，日志必须区分，否则失败后会误报「播放结束」。
    final completed = await _preview.play(filePath);
    AppLogger.log(
      'SpeechRatingBadge',
      '${completed ? "录音播放结束" : "录音播放未完成"}: '
          'prompt=${widget.attempt.promptId}, path=$filePath',
    );
  }

  Future<void> _stopPlayback() async {
    AppLogger.log(
      'SpeechRatingBadge',
      '停止录音播放: prompt=${widget.attempt.promptId}, '
          'path=${widget.attempt.filePath ?? "none"}',
    );
    await _preview.stop();
  }

  /// 无 ASR 结果但有录音时的降级胶囊：显示「录音」+ 播放图标。
  Widget _buildRecordingOnlyBadge(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark
        ? theme.colorScheme.onSurface.withValues(alpha: 0.8)
        : theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final bgColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.3)
        : theme.colorScheme.outline.withValues(alpha: 0.2);

    return TappableWrapper(
      onTap: _handleTap,
      feedbackType: TapFeedback.opacity,
      pressedOpacity: 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.l10n.listenAndRepeatRecordingOnly,
              style: theme.textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            _buildPlaybackIcon(textColor.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  String _ratingLabel() {
    final score = widget.attempt.score ?? 0;
    if (score >= widget.thresholds.perfect) {
      return widget.l10n.listenAndRepeatRatingPerfect;
    }
    if (score >= widget.thresholds.excellent) {
      return widget.l10n.listenAndRepeatRatingExcellent;
    }
    if (score >= widget.thresholds.good) {
      return widget.l10n.listenAndRepeatRatingGood;
    }
    if (score >= widget.thresholds.fair) {
      return widget.l10n.listenAndRepeatRatingFair;
    }
    return widget.l10n.listenAndRepeatRatingKeepGoing;
  }

  String _feedbackText() {
    return switch (widget.attempt.status) {
      SpeechPracticeAttemptStatus.noEnglishDetected =>
        widget.l10n.listenAndRepeatRecognitionNoEnglish,
      SpeechPracticeAttemptStatus.permissionDenied =>
        widget.l10n.listenAndRepeatRecognitionPermissionDenied,
      SpeechPracticeAttemptStatus.unavailable =>
        widget.l10n.listenAndRepeatRecognitionUnavailable,
      SpeechPracticeAttemptStatus.error =>
        widget.l10n.listenAndRepeatRecognitionError,
      SpeechPracticeAttemptStatus.awaitingFinal ||
      SpeechPracticeAttemptStatus.passed ||
      SpeechPracticeAttemptStatus.belowThreshold ||
      SpeechPracticeAttemptStatus.recording ||
      SpeechPracticeAttemptStatus.idle => '',
    };
  }

  Color _statusColor(ThemeData theme) {
    return switch (widget.attempt.status) {
      SpeechPracticeAttemptStatus.passed => const Color(0xFF2E9B51),
      SpeechPracticeAttemptStatus.awaitingFinal => theme.colorScheme.primary,
      SpeechPracticeAttemptStatus.belowThreshold ||
      SpeechPracticeAttemptStatus.noEnglishDetected ||
      SpeechPracticeAttemptStatus.permissionDenied ||
      SpeechPracticeAttemptStatus.unavailable ||
      SpeechPracticeAttemptStatus.error => theme.colorScheme.error,
      _ => theme.colorScheme.onSurface,
    };
  }

  _RatingBadgeStyle _ratingStyle(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final score = widget.attempt.score ?? 0;

    if (score >= widget.thresholds.perfect) {
      return isDark
          ? const _RatingBadgeStyle(
              textColor: Color(0xFFFFE082),
              backgroundStart: Color(0x33C9A030),
              backgroundEnd: Color(0x1A7A5F14),
              borderColor: Color(0x40E0B84A),
            )
          : const _RatingBadgeStyle(
              textColor: Color(0xFF8B6914),
              backgroundStart: Color(0xFFFFF8E1),
              backgroundEnd: Color(0xFFFFF0B8),
              borderColor: Color(0xFFE0C068),
            );
    }
    if (score >= widget.thresholds.excellent) {
      return isDark
          ? const _RatingBadgeStyle(
              textColor: Color(0xFFB9F5C8),
              backgroundStart: Color(0x3347B66B),
              backgroundEnd: Color(0x1A245B38),
              borderColor: Color(0x4057C878),
            )
          : const _RatingBadgeStyle(
              textColor: Color(0xFF1E7A3D),
              backgroundStart: Color(0xFFEAF8EF),
              backgroundEnd: Color(0xFFDDF2E4),
              borderColor: Color(0xFFA8D6B6),
            );
    }
    if (score >= widget.thresholds.good) {
      return isDark
          ? const _RatingBadgeStyle(
              textColor: Color(0xFFE4F3B2),
              backgroundStart: Color(0x33A4B84B),
              backgroundEnd: Color(0x1A56611F),
              borderColor: Color(0x40BDD460),
            )
          : const _RatingBadgeStyle(
              textColor: Color(0xFF687A18),
              backgroundStart: Color(0xFFF6F8DF),
              backgroundEnd: Color(0xFFEEF3C8),
              borderColor: Color(0xFFD6DD9A),
            );
    }
    if (score >= widget.thresholds.fair) {
      return isDark
          ? const _RatingBadgeStyle(
              textColor: Color(0xFFF7D79B),
              backgroundStart: Color(0x33C68A38),
              backgroundEnd: Color(0x1A6D4617),
              borderColor: Color(0x40E0A450),
            )
          : const _RatingBadgeStyle(
              textColor: Color(0xFF8A5A14),
              backgroundStart: Color(0xFFFFF1DD),
              backgroundEnd: Color(0xFFF9E3BF),
              borderColor: Color(0xFFE6C48C),
            );
    }
    return isDark
        ? const _RatingBadgeStyle(
            textColor: Color(0xFFB0BEC5),
            backgroundStart: Color(0x33607D8B),
            backgroundEnd: Color(0x1A37474F),
            borderColor: Color(0x4078909C),
          )
        : const _RatingBadgeStyle(
            textColor: Color(0xFF546E7A),
            backgroundStart: Color(0xFFECEFF1),
            backgroundEnd: Color(0xFFE0E4E8),
            borderColor: Color(0xFFB0BEC5),
          );
  }
}

/// 评级 Badge 内部样式
class _RatingBadgeStyle {
  final Color textColor;
  final Color backgroundStart;
  final Color backgroundEnd;
  final Color borderColor;

  const _RatingBadgeStyle({
    required this.textColor,
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.borderColor,
  });
}
