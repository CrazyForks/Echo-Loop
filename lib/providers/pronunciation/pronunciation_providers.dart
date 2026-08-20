import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/pronunciation/pronunciation_clip.dart';
import '../../services/app_logger.dart';
import '../../services/download/download_failure.dart';
import '../../services/pronunciation/local_audio_clip_player.dart';
import '../../services/pronunciation/pronunciation_library_manager.dart';
import '../../services/pronunciation/pronunciation_repository.dart';
import '../../services/reliable_http_downloader.dart';
import '../../utils/text_normalize.dart';
import '../dictionary_provider.dart';
import '../short_audio_player_provider.dart';
import '../tts/tts_controller_provider.dart';

enum PronunciationLibraryStatus {
  notDownloaded,
  downloading,
  installing,
  ready,
  failed,
}

class PronunciationLibraryState {
  const PronunciationLibraryState({
    this.status = PronunciationLibraryStatus.notDownloaded,
    this.progress = 0,
    this.localSizeBytes = 0,
    this.failure,
  });

  final PronunciationLibraryStatus status;
  final double progress;
  final int localSizeBytes;
  final DownloadFailureKind? failure;

  bool get isReady => status == PronunciationLibraryStatus.ready;
}

final pronunciationLibraryManagerProvider =
    Provider<PronunciationLibraryManager>((ref) {
      final manager = PronunciationLibraryManager();
      ref.onDispose(manager.dispose);
      return manager;
    });

final pronunciationRepositoryProvider = Provider<PronunciationRepository>((
  ref,
) {
  final repository = PronunciationRepository();
  ref.onDispose(repository.close);
  return repository;
});

final pronunciationLibraryProvider =
    NotifierProvider<PronunciationLibraryNotifier, PronunciationLibraryState>(
      PronunciationLibraryNotifier.new,
    );

class PronunciationLibraryNotifier extends Notifier<PronunciationLibraryState> {
  CancelToken? _cancelToken;
  Future<void>? _task;
  int _sessionId = 0;

  @override
  PronunciationLibraryState build() {
    ref.onDispose(() => _cancelToken?.cancel('provider disposed'));
    ref.listen<DictionaryState>(dictionaryProvider, (_, next) {
      if (next.status == DictionaryStatus.downloaded) {
        unawaited(ensureDownloaded());
      }
    }, fireImmediately: true);
    return const PronunciationLibraryState();
  }

  Future<void> ensureDownloaded() async {
    if (ref.read(dictionaryProvider).status != DictionaryStatus.downloaded) {
      return;
    }
    return _runTask(_ensureInstalled);
  }

  Future<void> retryDownload() => _runTask(_download);

  /// 即使已有可用版本也重新下载；安装成功前 repository 保持旧连接可用。
  Future<void> redownload() => _runTask(_download);

  Future<void> _runTask(Future<void> Function() operation) async {
    final running = _task;
    if (running != null) return running;
    final task = operation();
    _task = task;
    try {
      await task;
    } finally {
      if (identical(_task, task)) _task = null;
    }
  }

  Future<void> _ensureInstalled() async {
    final manager = ref.read(pronunciationLibraryManagerProvider);
    await manager.recoverInterruptedInstall();
    // 重新下载在旧库可用时也必须恢复，不能被已安装版本短路。
    if (await manager.hasPendingInstall()) {
      await _download();
      return;
    }
    final paths = await manager.installedPaths();
    if (paths != null) {
      _open(paths);
      state = PronunciationLibraryState(
        status: PronunciationLibraryStatus.ready,
        progress: 1,
        localSizeBytes: await manager.localSizeBytes(),
      );
      return;
    }
    await _download();
  }

  Future<void> _download() async {
    final sessionId = ++_sessionId;
    final cancelToken = CancelToken();
    _cancelToken?.cancel('new pronunciation download');
    _cancelToken = cancelToken;
    state = const PronunciationLibraryState(
      status: PronunciationLibraryStatus.downloading,
    );
    final manager = ref.read(pronunciationLibraryManagerProvider);
    try {
      final paths = await manager.downloadAndInstall(
        cancelToken: cancelToken,
        onDownloadProgress: (progress) {
          if (!_isCurrent(sessionId, cancelToken)) return;
          state = PronunciationLibraryState(
            status: PronunciationLibraryStatus.downloading,
            progress: progress,
          );
        },
        onInstalling: () {
          if (!_isCurrent(sessionId, cancelToken)) return;
          state = const PronunciationLibraryState(
            status: PronunciationLibraryStatus.installing,
            progress: 1,
          );
        },
      );
      if (!_isCurrent(sessionId, cancelToken)) return;
      _open(paths);
      state = PronunciationLibraryState(
        status: PronunciationLibraryStatus.ready,
        progress: 1,
        localSizeBytes: await manager.localSizeBytes(),
      );
      AppLogger.log('Pronunciation', 'library ready');
    } catch (error, stackTrace) {
      if (!_isCurrent(sessionId, cancelToken) || _isCancelled(error)) return;
      AppLogger.log('Pronunciation', 'download failed: $error\n$stackTrace');
      state = PronunciationLibraryState(
        status: PronunciationLibraryStatus.failed,
        failure: classifyDownloadFailure(error),
      );
    }
  }

  bool _isCurrent(int sessionId, CancelToken token) =>
      sessionId == _sessionId && identical(_cancelToken, token);

  bool _isCancelled(Object error) =>
      (error is DioException && error.type == DioExceptionType.cancel) ||
      (error is ReliableDownloadException &&
          error.kind == ReliableDownloadFailure.cancelled);

  void _open(PronunciationLibraryPaths paths) {
    ref
        .read(pronunciationRepositoryProvider)
        .open(paths.database, paths.audioDirectory);
  }
}

final pronunciationClipsProvider =
    Provider.family<List<PronunciationClip>, String>((ref, word) {
      // 订阅状态变化以便安装完成后刷新；重新下载期间 repository 仍保持旧版连接，
      // 不因 UI 状态切到 downloading 而中断已有离线发音。
      ref.watch(pronunciationLibraryProvider);
      final repository = ref.read(pronunciationRepositoryProvider);
      if (!repository.isAvailable) return const [];
      return repository.lookupSingleWord(normalizeWord(word));
    });

class TextPlaybackState {
  const TextPlaybackState({this.playingKey});
  final String? playingKey;
}

final textPlaybackProvider =
    NotifierProvider<TextPlaybackController, TextPlaybackState>(
      TextPlaybackController.new,
    );

class TextPlaybackController extends Notifier<TextPlaybackState> {
  int _sessionId = 0;
  LocalAudioClipPlayer? _player;

  @override
  TextPlaybackState build() {
    return const TextPlaybackState();
  }

  /// 统一朗读文本：单个单词优先离线 Opus，未命中、多词或本地播放失败时回退 TTS。
  ///
  /// 通用播放入口均调用本方法，避免页面分别判断离线发音状态而造成预热与点击
  /// 播放走不同链路。
  Future<void> speak(String text, {String? key}) async {
    final clips = ref.read(pronunciationClipsProvider(text));
    if (clips.isNotEmpty) {
      await play(clips.first, fallbackText: text, fallbackKey: key ?? text);
      return;
    }
    await ref
        .read(ttsControllerProvider.notifier)
        .speak(text, key: key ?? text);
  }

  /// 顺序播放单个单词命中的全部离线发音。
  ///
  /// 词组不会进入此入口，仍由 [speak] 保持原有的单条离线发音或 TTS 语义。
  /// 本地音频单条失败时继续尝试后续条目；只有全部失败才回退一次 TTS。
  Future<void> speakAllSingleWordPronunciations(
    String word, {
    String? key,
  }) async {
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty || RegExp(r'\s').hasMatch(trimmedWord)) {
      await speak(word, key: key);
      return;
    }
    final clips = ref.read(pronunciationClipsProvider(trimmedWord));
    if (clips.length <= 1) {
      await speak(trimmedWord, key: key);
      return;
    }

    final sessionId = ++_sessionId;
    await ref.read(ttsControllerProvider.notifier).stop();
    final LocalAudioClipPlayer player;
    final currentPlayer = _player;
    if (currentPlayer != null) {
      player = currentPlayer;
    } else {
      player = ref.read(shortAudioPlayerProvider);
      _player = player;
    }
    var completedAnyClip = false;
    for (var index = 0; index < clips.length; index++) {
      if (sessionId != _sessionId) return;
      final clip = clips[index];
      state = TextPlaybackState(playingKey: clip.playbackKey);
      final result = await player.playFile(
        clip.absolutePath,
        playbackKey: clip.playbackKey,
      );
      if (sessionId != _sessionId || result == AudioPlaybackResult.cancelled) {
        return;
      }
      completedAnyClip |= result == AudioPlaybackResult.completed;
      if (index < clips.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    if (sessionId != _sessionId) return;
    state = const TextPlaybackState();
    if (!completedAnyClip) {
      await ref
          .read(ttsControllerProvider.notifier)
          .speak(trimmedWord, key: key ?? trimmedWord);
    }
  }

  Future<void> play(
    PronunciationClip clip, {
    required String fallbackText,
    String? fallbackKey,
  }) async {
    final sessionId = ++_sessionId;
    state = TextPlaybackState(playingKey: clip.playbackKey);
    await ref.read(ttsControllerProvider.notifier).stop();
    final LocalAudioClipPlayer player;
    final currentPlayer = _player;
    if (currentPlayer != null) {
      player = currentPlayer;
    } else {
      player = ref.read(shortAudioPlayerProvider);
      _player = player;
    }
    final result = await player.playFile(
      clip.absolutePath,
      playbackKey: clip.playbackKey,
    );
    if (sessionId != _sessionId) return;
    state = const TextPlaybackState();
    if (result == AudioPlaybackResult.failed) {
      await ref
          .read(ttsControllerProvider.notifier)
          .speak(fallbackText, key: fallbackKey ?? clip.playbackKey);
    }
  }

  Future<void> stop() async {
    _sessionId++;
    await _player?.stop();
    state = const TextPlaybackState();
  }
}
