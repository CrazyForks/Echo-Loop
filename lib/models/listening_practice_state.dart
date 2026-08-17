import 'audio_item.dart';
import 'sentence.dart';
import 'playback_settings.dart';

enum PlaylistMode { full, bookmarks }

class ListeningPracticeState {
  final AudioItem? currentAudioItem;
  final List<Sentence> sentences;
  final int? currentFullIndex;
  final int? currentBookmarkIndex;
  final int? lastPlayedFullIndex;
  final int? lastPlayedBookmarkIndex;
  final PlaybackSettings fullSettings;
  final PlaybackSettings bookmarkSettings;
  final PlaylistMode playlistMode;
  final Set<int> bookmarkedIndices;
  final bool isLoading;

  /// 逻辑播放态：controller 当前是否处于「播放意图」。
  ///
  /// 这是播放/暂停按钮图标的唯一真相源，由 controller 在起播/暂停/停止/自然播完
  /// 等明确入口显式维护，**不**读 just_audio 的 `AudioPlayer.playing`——后者在
  /// 自然播完（completed）后仍为 true，会让图标误显「暂停」。
  final bool isPlaying;

  /// 整篇循环已完成的遍数（controller 内部计数的只读镜像）。
  ///
  /// 供状态栏展示「当前第几遍」：播放中当前正在播第 `wholeLoopsDone + 1` 遍。
  final int wholeLoopsDone;

  /// 当前句单句循环已完成的遍数（controller 内部计数的只读镜像）。
  ///
  /// 供状态栏展示「当前句第几遍」：播放中当前正在播第 `sentenceRepeatsDone + 1` 遍。
  final int sentenceRepeatsDone;

  const ListeningPracticeState({
    this.currentAudioItem,
    this.sentences = const [],
    this.currentFullIndex,
    this.currentBookmarkIndex,
    this.lastPlayedFullIndex,
    this.lastPlayedBookmarkIndex,
    PlaybackSettings? settings,
    PlaybackSettings fullSettings = const PlaybackSettings(),
    PlaybackSettings bookmarkSettings = kDefaultBookmarkPlaybackSettings,
    this.playlistMode = PlaylistMode.full,
    this.bookmarkedIndices = const {},
    this.isLoading = false,
    this.isPlaying = false,
    this.wholeLoopsDone = 0,
    this.sentenceRepeatsDone = 0,
  }) : fullSettings = settings ?? fullSettings,
       bookmarkSettings = settings ?? bookmarkSettings;

  /// 当前激活 Tab 生效的播放设置。
  PlaybackSettings get settings =>
      playlistMode == PlaylistMode.bookmarks ? bookmarkSettings : fullSettings;

  // 计算属性
  List<Sentence> get bookmarkedSentences =>
      sentences.where((s) => bookmarkedIndices.contains(s.index)).toList();

  Sentence? get currentSentence =>
      currentFullIndex != null && currentFullIndex! < sentences.length
      ? sentences[currentFullIndex!]
      : null;

  bool get hasAudio => currentAudioItem != null;
  bool get hasSentences => sentences.isNotEmpty;

  /// 当前生效播放列表：全文模式=全部句子；收藏模式=收藏句子。
  List<Sentence> get playableSentences =>
      playlistMode == PlaylistMode.bookmarks ? bookmarkedSentences : sentences;

  /// 当前句在 [playableSentences] 中的序号（0-based）。列表为空返回 null。
  int? get currentPlayablePosition {
    final playable = playableSentences;
    if (playable.isEmpty) return null;
    if (playlistMode == PlaylistMode.bookmarks) {
      final ci = currentBookmarkIndex;
      if (ci == null) return 0;
      final p = playable.indexWhere((s) => s.index == ci);
      return p == -1 ? 0 : p;
    }
    final ci = currentFullIndex;
    if (ci == null || ci < 0 || ci >= playable.length) return 0;
    return ci;
  }

  /// 是否已在播放列表第一句（驱动"上一句"按钮禁用态）。
  bool get isFirstSentence => (currentPlayablePosition ?? 0) <= 0;

  /// 是否已在播放列表最后一句（驱动"下一句"按钮禁用态）。
  bool get isLastSentence {
    final playable = playableSentences;
    if (playable.isEmpty) return true;
    return (currentPlayablePosition ?? 0) >= playable.length - 1;
  }

  ListeningPracticeState copyWith({
    AudioItem? currentAudioItem,
    bool clearCurrentAudioItem = false,
    List<Sentence>? sentences,
    int? currentFullIndex,
    bool clearCurrentFullIndex = false,
    int? currentBookmarkIndex,
    bool clearCurrentBookmarkIndex = false,
    int? lastPlayedFullIndex,
    bool clearLastPlayedFullIndex = false,
    int? lastPlayedBookmarkIndex,
    bool clearLastPlayedBookmarkIndex = false,
    PlaybackSettings? fullSettings,
    PlaybackSettings? bookmarkSettings,
    PlaybackSettings? settings,
    PlaylistMode? playlistMode,
    Set<int>? bookmarkedIndices,
    bool? isLoading,
    bool? isPlaying,
    int? wholeLoopsDone,
    int? sentenceRepeatsDone,
  }) {
    final nextPlaylistMode = playlistMode ?? this.playlistMode;
    var nextFullSettings = fullSettings ?? this.fullSettings;
    var nextBookmarkSettings = bookmarkSettings ?? this.bookmarkSettings;

    if (settings != null) {
      if (nextPlaylistMode == PlaylistMode.bookmarks) {
        nextBookmarkSettings = settings;
      } else {
        nextFullSettings = settings;
      }
    }

    return ListeningPracticeState(
      currentAudioItem: clearCurrentAudioItem
          ? null
          : (currentAudioItem ?? this.currentAudioItem),
      sentences: sentences ?? this.sentences,
      currentFullIndex: clearCurrentFullIndex
          ? null
          : (currentFullIndex ?? this.currentFullIndex),
      currentBookmarkIndex: clearCurrentBookmarkIndex
          ? null
          : (currentBookmarkIndex ?? this.currentBookmarkIndex),
      lastPlayedFullIndex: clearLastPlayedFullIndex
          ? null
          : (lastPlayedFullIndex ?? this.lastPlayedFullIndex),
      lastPlayedBookmarkIndex: clearLastPlayedBookmarkIndex
          ? null
          : (lastPlayedBookmarkIndex ?? this.lastPlayedBookmarkIndex),
      fullSettings: nextFullSettings,
      bookmarkSettings: nextBookmarkSettings,
      playlistMode: nextPlaylistMode,
      bookmarkedIndices: bookmarkedIndices ?? this.bookmarkedIndices,
      isLoading: isLoading ?? this.isLoading,
      isPlaying: isPlaying ?? this.isPlaying,
      wholeLoopsDone: wholeLoopsDone ?? this.wholeLoopsDone,
      sentenceRepeatsDone: sentenceRepeatsDone ?? this.sentenceRepeatsDone,
    );
  }
}
