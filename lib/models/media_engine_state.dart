/// media_kit 链路的播放状态。
///
/// 不复用 AudioEngineState：AudioEngineState 带有 just_audio clip 补偿语义，
/// media_kit 链路的位置天然是绝对时间。
class MediaEngineState {
  const MediaEngineState({
    this.sessionId = 0,
    this.isLoading = false,
    this.errorMessage,
    this.currentMediaId,
    this.totalDuration,
    this.videoTrackEnabled = true,
    this.subtitleTrackEnabled = true,
  });

  final int sessionId;
  final bool isLoading;
  final String? errorMessage;
  final String? currentMediaId;
  final Duration? totalDuration;
  final bool videoTrackEnabled;
  final bool subtitleTrackEnabled;

  MediaEngineState copyWith({
    int? sessionId,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? currentMediaId,
    bool clearCurrentMediaId = false,
    Duration? totalDuration,
    bool clearTotalDuration = false,
    bool? videoTrackEnabled,
    bool? subtitleTrackEnabled,
  }) {
    return MediaEngineState(
      sessionId: sessionId ?? this.sessionId,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      currentMediaId: clearCurrentMediaId
          ? null
          : currentMediaId ?? this.currentMediaId,
      totalDuration: clearTotalDuration
          ? null
          : totalDuration ?? this.totalDuration,
      videoTrackEnabled: videoTrackEnabled ?? this.videoTrackEnabled,
      subtitleTrackEnabled: subtitleTrackEnabled ?? this.subtitleTrackEnabled,
    );
  }
}
