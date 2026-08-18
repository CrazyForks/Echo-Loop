/// 离线发音用途。
enum PronunciationReason {
  adjective,
  noun,
  nounAdjective,
  verb,
  pastTense,
  presentTense,
  interjection,
}

/// 发音库中的一条可播放音频。
class PronunciationClip {
  const PronunciationClip({
    required this.word,
    required this.locale,
    required this.audioFilename,
    required this.absolutePath,
    required this.reason,
  });

  final String word;
  final String locale;
  final String audioFilename;
  final String absolutePath;
  final PronunciationReason? reason;

  String get playbackKey => 'pronunciation:$audioFilename';
}

/// 从受控音频文件名解析用途；未知后缀按普通发音处理。
PronunciationReason? pronunciationReasonFromFilename(String filename) {
  const suffixes = <String, PronunciationReason>{
    '_v_present.opus': PronunciationReason.presentTense,
    '_v_past.opus': PronunciationReason.pastTense,
    '_n_adj.opus': PronunciationReason.nounAdjective,
    '_interj.opus': PronunciationReason.interjection,
    '_adj.opus': PronunciationReason.adjective,
    '_n.opus': PronunciationReason.noun,
    '_v.opus': PronunciationReason.verb,
  };
  for (final entry in suffixes.entries) {
    if (filename.endsWith(entry.key)) return entry.value;
  }
  return null;
}
