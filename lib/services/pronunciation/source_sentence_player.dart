import '../../database/daos/audio_item_dao.dart';
import '../../models/sentence.dart';
import '../subtitle_parser.dart';
import 'local_audio_clip_player.dart';
import 'local_audio_range_player.dart';

/// 收藏词汇与意群共用的来源句播放编排。
///
/// 只负责一次性来源句试听：原音区间成功时不触发 TTS，原音不可用时
/// 才通过注入的回调朗读文本。播放器本身由调用方注入，保持生命周期归属。
class SourceSentencePlayer {
  SourceSentencePlayer({
    required AudioItemDao audioItemDao,
    required LocalAudioClipPlayer audioClipPlayer,
    required Future<void> Function(String text, String playbackKey) speak,
  }) : _audioItemDao = audioItemDao,
       _audioClipPlayer = audioClipPlayer,
       _speak = speak;

  final AudioItemDao _audioItemDao;
  final LocalAudioClipPlayer _audioClipPlayer;
  final Future<void> Function(String text, String playbackKey) _speak;

  /// 播放来源句；返回 true 表示原音成功，false 表示已回退或无可播放内容。
  Future<bool> play({
    required String? audioItemId,
    required int? sentenceIndex,
    required String? sentenceText,
    required int? sentenceStartMs,
    required int? sentenceEndMs,
    required String playbackKey,
  }) async {
    final text = sentenceText?.trim();
    try {
      final row = audioItemId == null
          ? null
          : await _audioItemDao.getById(audioItemId);
      if (row != null) {
        final filePath = await audioItemFromDatabaseRow(row).getFullAudioPath();
        final range = _resolveStoredRange(sentenceStartMs, sentenceEndMs);
        if (filePath != null && range != null) {
          switch (await _audioClipPlayer.playRangeFile(
            filePath,
            start: range.$1,
            end: range.$2,
            playbackKey: playbackKey,
          )) {
            case AudioPlaybackResult.completed:
              return true;
            case AudioPlaybackResult.cancelled:
              return false;
            case AudioPlaybackResult.failed:
              break;
          }
        }

        final srt = await _audioItemDao.getTranscriptSrt(row.id);
        if (srt != null && srt.isNotEmpty && text != null) {
          final sentences = await SubtitleParser.parseSubtitleString(srt);
          Sentence? sentence =
              sentenceIndex != null &&
                  sentenceIndex >= 0 &&
                  sentenceIndex < sentences.length
              ? sentences[sentenceIndex]
              : null;
          if (sentence == null || sentence.text.trim() != text) {
            sentence = sentences.cast<Sentence?>().firstWhere(
              (candidate) => candidate!.text.trim() == text,
              orElse: () => null,
            );
          }
          if (filePath != null && sentence != null) {
            switch (await _audioClipPlayer.playRangeFile(
              filePath,
              start: sentence.startTime,
              end: sentence.endTime,
              playbackKey: playbackKey,
            )) {
              case AudioPlaybackResult.completed:
                return true;
              case AudioPlaybackResult.cancelled:
                return false;
              case AudioPlaybackResult.failed:
                break;
            }
          }
        }
      }
    } catch (_) {
      // 原音链路失败时统一进入 TTS 兜底。
    }
    if (text != null && text.isNotEmpty) {
      await _speak(text, playbackKey);
    }
    return false;
  }

  (Duration, Duration)? _resolveStoredRange(int? startMs, int? endMs) {
    if (startMs == null || endMs == null || endMs - startMs < 200) {
      return null;
    }
    return (Duration(milliseconds: startMs), Duration(milliseconds: endMs));
  }
}
