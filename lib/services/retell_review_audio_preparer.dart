/// 复述评估上传音频的临时转码服务。
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';
import 'package:uuid/uuid.dart';

import '../features/audio_import/audio_transcode_service.dart';

/// 供复述评估 controller 注入的音频准备接口。
abstract class RetellReviewAudioPreparer {
  /// 生成仅用于本次服务端转录的低码率音频。
  Future<File> prepare(File source);
}

/// 无法生成服务端可接受的临时音频。
class RetellReviewAudioPreparationException implements Exception {
  const RetellReviewAudioPreparationException();
}

/// 使用既有 FFmpeg 转码能力准备 16 kHz 单声道 AAC 文件。
class FfmpegRetellReviewAudioPreparer implements RetellReviewAudioPreparer {
  final AudioTranscodeService _transcodeService;
  final Uuid _uuid;

  FfmpegRetellReviewAudioPreparer({
    AudioTranscodeService? transcodeService,
    Uuid? uuid,
  }) : _transcodeService = transcodeService ?? AudioTranscodeService(),
       _uuid = uuid ?? const Uuid();

  @override
  Future<File> prepare(File source) async {
    final directory = await getTemporaryDirectory();
    final output = File(p.join(directory.path, '${_uuid.v4()}.m4a'));
    final success = await _transcodeService.transcodeForReviewEvaluation(
      source: source,
      output: output,
    );
    if (!success) throw const RetellReviewAudioPreparationException();
    return output;
  }
}
