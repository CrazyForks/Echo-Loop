import '../../database/daos/audio_item_dao.dart';
import '../../models/audio_item.dart' as model;
import '../../models/sentence.dart';
import '../subtitle_parser.dart';
import 'local_audio_clip_player.dart';

/// 收藏词汇与意群共用的来源句播放编排。
///
/// 只负责一次性来源句试听：原音区间成功时不触发 TTS，原音不可用时
/// 才通过注入的回调朗读文本。播放器本身由调用方注入，保持生命周期归属。
class SourceSentencePlayer {
  SourceSentencePlayer({
    required AudioItemDao audioItemDao,
    required LocalAudioClipPlayer audioClipPlayer,
    required Future<void> Function(String text) speak,
  }) : _audioItemDao = audioItemDao,
       _audioClipPlayer = audioClipPlayer,
       _speak = speak;

  final AudioItemDao _audioItemDao;
  final LocalAudioClipPlayer _audioClipPlayer;
  final Future<void> Function(String text) _speak;

  /// 播放来源句；返回 true 表示原音成功，false 表示已回退或无可播放内容。
  Future<bool> play({
    required String? audioItemId,
    required int? sentenceIndex,
    required String? sentenceText,
    required int? sentenceStartMs,
    required int? sentenceEndMs,
  }) async {
    final text = sentenceText?.trim();
    try {
      final row = audioItemId == null
          ? null
          : await _audioItemDao.getById(audioItemId);
      if (row != null) {
        final audioItem = model.AudioItem(
          id: row.id,
          name: row.name,
          audioPath: row.audioPath,
          transcriptPath: row.transcriptPath,
          addedDate: row.addedDate,
          totalDuration: row.totalDuration,
          sentenceCount: row.sentenceCount,
          wordCount: row.wordCount,
          isPinned: row.isPinned,
          transcriptSource: model.TranscriptSource.fromIndex(
            row.transcriptSource,
          ),
          audioSha256: row.audioSha256,
          originalAudioSha256: row.originalAudioSha256,
          transcriptLanguage: row.transcriptLanguage,
        );
        final filePath = await audioItem.getFullAudioPath();
        final range = _resolveStoredRange(sentenceStartMs, sentenceEndMs);
        if (filePath != null && range != null) {
          if (await _audioClipPlayer.playRangeFile(
            filePath,
            start: range.$1,
            end: range.$2,
          )) {
            return true;
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
          if (filePath != null &&
              sentence != null &&
              await _audioClipPlayer.playRangeFile(
                filePath,
                start: sentence.startTime,
                end: sentence.endTime,
              )) {
            return true;
          }
        }
      }
    } catch (_) {
      // 原音链路失败时统一进入 TTS 兜底。
    }
    if (text != null && text.isNotEmpty) {
      await _speak(text);
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
