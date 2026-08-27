/// 内置离线发音包资源目录。
class PronunciationSpec {
  const PronunciationSpec({
    required this.resourceId,
    required this.archiveUrl,
    required this.archiveSha256,
    required this.estimatedDownloadBytes,
  });

  final String resourceId;
  final String archiveUrl;
  final String archiveSha256;
  final int estimatedDownloadBytes;
}

/// 当前发布的离线发音包资源。
const pronunciationSpec = PronunciationSpec(
  resourceId: 'pronunciation-v2',
  archiveUrl: 'https://cdn.echo-loop.top/dictionary/pronunciation-v2.zip',
  archiveSha256:
      'db1bf8c8ec953f48ed05e22f8254cd8385f3c26f0acb630f73aedf14bbb6a1ca',
  estimatedDownloadBytes: 41379389,
);
