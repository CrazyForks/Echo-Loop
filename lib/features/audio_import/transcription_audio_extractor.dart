import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

import '../../services/app_logger.dart';
import 'audio_transcode_service.dart';

/// 视频转录前的音轨抽取服务。
///
/// 视频文件体积远大于其音轨，若直接上传整段视频给转录服务：一是浪费上传带宽
/// （常见 mp4 十几 MB，音轨往往只有 1~2 MB），二是需要服务端额外解码视频。
/// 因此视频条目在上传前先用 ffmpeg 抽出音轨（m4a）只上传音频；**原视频文件
/// 保持不动**，后续仍用于真实视频播放。
///
/// 抽取失败不阻塞转录：调用方回退为上传原视频（后端本就兼容 mp4 容器）。
class TranscriptionAudioExtractor {
  /// [transcodeService] 副作用注入点，测试时可传入 mock（见 CLAUDE.md §2.5）。
  TranscriptionAudioExtractor({AudioTranscodeService? transcodeService})
    : _transcodeService = transcodeService ?? AudioTranscodeService();

  final AudioTranscodeService _transcodeService;

  static const _logTag = 'TranscriptionAudioExtract';

  /// 把 [videoAbsolutePath] 的音轨抽为临时 m4a，写入
  /// `[dataDir]/tmp/transcription/` 下，返回临时文件绝对路径。
  ///
  /// 临时文件名用视频文件名（视频已按 sha 命名，天然唯一且可覆盖复用，不会堆积）。
  /// 抽取成功返回临时 m4a 路径；失败返回 `null`（调用方回退上传原视频）。
  /// 临时文件由调用方在上传完成后删除。
  Future<String?> extractAudioTrack({
    required Directory dataDir,
    required String videoAbsolutePath,
  }) async {
    final tmpDir = Directory(p.join(dataDir.path, 'tmp', 'transcription'));
    await tmpDir.create(recursive: true);
    final baseName = p.basenameWithoutExtension(videoAbsolutePath);
    final output = File(p.join(tmpDir.path, '$baseName.m4a'));

    final ok = await _transcodeService.transcodeToFile(
      source: File(videoAbsolutePath),
      output: output,
    );
    if (!ok) {
      AppLogger.log(_logTag, '抽音轨失败 video=${p.basename(videoAbsolutePath)}');
      return null;
    }
    AppLogger.log(_logTag, '抽音轨成功 output=${p.basename(output.path)}');
    return output.path;
  }
}
