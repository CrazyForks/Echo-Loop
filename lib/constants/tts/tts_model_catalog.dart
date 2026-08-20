/// 内置 TTS 模型的发布元数据目录。
///
/// 这是客户端 TTS 模型元数据的唯一真相来源：模型 ID、下载地址、归档大小、
/// SHA-256 以及安装时需要定位的模型文件均在此声明。下载器、Provider 和 UI
/// 后续应只读取本目录，不要在业务代码中复制这些值或重新拼接下载地址。
library;

import '../../services/tts/tts_engine.dart'
    show KokoroModelVariant, TtsAccent;

/// 单个 TTS 模型归档的通用发布元数据。
///
/// [archiveSizeBytes] 是 CDN 返回的压缩归档大小，而不是解压后的本地占用空间。
/// 某个已发布模型尚未完成尺寸登记时使用 `null`；禁止用估算值代替真实字节数。
class TtsModelMetadata {
  /// 稳定模型 ID，同时作为下载状态和缓存分桶的标识。
  final String id;

  /// 完整、可直接请求的 HTTPS 下载地址。
  final String downloadUrl;

  /// 压缩归档的精确大小（字节）；未登记时为 null。
  final int? archiveSizeBytes;

  /// 压缩归档的 SHA-256（小写十六进制）。
  final String sha256;

  /// 模型安装目录名。通常与 [id] 相同，但显式保存以支持未来迁移目录。
  final String localDirectoryName;

  /// 解包后供推理引擎加载的模型文件名。
  final String modelFileName;

  const TtsModelMetadata({
    required this.id,
    required this.downloadUrl,
    required this.archiveSizeBytes,
    required this.sha256,
    required this.localDirectoryName,
    required this.modelFileName,
  });
}

/// Kokoro 模型变体及其发布元数据。
class KokoroModelMetadata extends TtsModelMetadata {
  /// 与设置和 Provider 使用的 Kokoro 变体枚举。
  final KokoroModelVariant variant;

  const KokoroModelMetadata({
    required this.variant,
    required super.id,
    required super.downloadUrl,
    required super.archiveSizeBytes,
    required super.sha256,
    required super.localDirectoryName,
    required super.modelFileName,
  });
}

/// Piper 音色及其独立模型归档的发布元数据。
class PiperVoiceMetadata extends TtsModelMetadata {
  /// 设置偏好和缓存使用的兼容音色 ID（不含全局类型前缀）。
  final String voiceId;
  /// 音色口音，用于设置页分组和默认值校验。
  final TtsAccent accent;

  /// 设置页展示名称。
  final String displayName;

  /// 是否为女声，仅用于展示标签。
  final bool isFemale;

  const PiperVoiceMetadata({
    required this.voiceId,
    required this.accent,
    required this.displayName,
    required this.isFemale,
    required super.id,
    required super.downloadUrl,
    required super.archiveSizeBytes,
    required super.sha256,
    required super.localDirectoryName,
    required super.modelFileName,
  });
}

const _ttsCdnBaseUrl = 'https://cdn.echo-loop.top';

/// 默认 Piper 音色 ID（按口音区分）。
const piperTtsDefaultVoiceUsId = 'en_US-amy-medium';
const piperTtsDefaultVoiceUkId = 'en_GB-alan-medium';

/// Kokoro 模型目录。
const Map<KokoroModelVariant, KokoroModelMetadata> kokoroTtsModelCatalog = {
  KokoroModelVariant.fp32: KokoroModelMetadata(
    variant: KokoroModelVariant.fp32,
    id: 'kokoro-en-v0_19',
    downloadUrl: '$_ttsCdnBaseUrl/model/tts/kokoro-en-v0_19.tar.gz',
    // 仓库当前没有该归档的精确 Content-Length，登记后再填入真实值。
    archiveSizeBytes: null,
    sha256: 'd97c85ba5777bc226eca3a40312bb29dd8fd0e77546d4100abb7243b9b6ad137',
    localDirectoryName: 'kokoro-en-v0_19',
    modelFileName: 'model.onnx',
  ),
  KokoroModelVariant.int8: KokoroModelMetadata(
    variant: KokoroModelVariant.int8,
    id: 'kokoro-en-v0_19-int8',
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/kokoro-en-v0_19-int8-v2.tar.gz',
    // 仓库当前没有该归档的精确 Content-Length，登记后再填入真实值。
    archiveSizeBytes: null,
    sha256: '70fd7ff687d08245f9409557f58072f43eb8a5bf8a90e98dd3bb7f60e05b4b07',
    localDirectoryName: 'kokoro-en-v0_19-int8',
    modelFileName: 'model.int8.onnx',
  ),
};

/// Piper 音色模型目录，顺序保持设置页当前展示顺序。
const List<PiperVoiceMetadata> piperTtsModelCatalog = [
  PiperVoiceMetadata(
    id: 'piper-en_US-amy-medium',
    voiceId: 'en_US-amy-medium',
    displayName: 'Amy',
    accent: TtsAccent.us,
    isFemale: true,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_US-amy-medium.tar.gz',
    archiveSizeBytes: 67347129,
    sha256: 'ce4fc13a01c2b670f744c5d944469ac2c01b144f8f98ff7985d67d7402695c29',
    localDirectoryName: 'en_US-amy-medium',
    modelFileName: 'en_US-amy-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_US-lessac-medium',
    voiceId: 'en_US-lessac-medium',
    displayName: 'Lessac',
    accent: TtsAccent.us,
    isFemale: true,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_US-lessac-medium.tar.gz',
    archiveSizeBytes: 67358584,
    sha256: 'd0fd375de4be84199813d3c69b94ebf5b14ae5c291bda61315d0307eed039065',
    localDirectoryName: 'en_US-lessac-medium',
    modelFileName: 'en_US-lessac-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_US-ryan-medium',
    voiceId: 'en_US-ryan-medium',
    displayName: 'Ryan',
    accent: TtsAccent.us,
    isFemale: false,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_US-ryan-medium.tar.gz',
    archiveSizeBytes: 67370820,
    sha256: '49e5065dd3f17c27be2d29310887dbd17b924ebfb0fc24a6f82b7e96a34a44d4',
    localDirectoryName: 'en_US-ryan-medium',
    modelFileName: 'en_US-ryan-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_US-joe-medium',
    voiceId: 'en_US-joe-medium',
    displayName: 'Joe',
    accent: TtsAccent.us,
    isFemale: false,
    downloadUrl: '$_ttsCdnBaseUrl/model/tts/vits-piper-en_US-joe-medium.tar.gz',
    archiveSizeBytes: 67329430,
    sha256: 'c13190297212663f4371e365e239f7208ceeaae0e2d8ce5994456b42bb1e6799',
    localDirectoryName: 'en_US-joe-medium',
    modelFileName: 'en_US-joe-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_US-kristin-medium',
    voiceId: 'en_US-kristin-medium',
    displayName: 'Kristin',
    accent: TtsAccent.us,
    isFemale: true,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_US-kristin-medium.tar.gz',
    archiveSizeBytes: 67424191,
    sha256: '58988662c21850d05b5687043dc710a6c41bbf15814aff34e4be32c32cb377a8',
    localDirectoryName: 'en_US-kristin-medium',
    modelFileName: 'en_US-kristin-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_US-hfc_female-medium',
    voiceId: 'en_US-hfc_female-medium',
    displayName: 'Hannah',
    accent: TtsAccent.us,
    isFemale: true,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_US-hfc_female-medium.tar.gz',
    archiveSizeBytes: 67359748,
    sha256: 'b849044f82219e2b0d990d81e75b80cecedda53608b182299beffbeadfac33f0',
    localDirectoryName: 'en_US-hfc_female-medium',
    modelFileName: 'en_US-hfc_female-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_GB-alan-medium',
    voiceId: 'en_GB-alan-medium',
    displayName: 'Alan',
    accent: TtsAccent.uk,
    isFemale: false,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_GB-alan-medium.tar.gz',
    archiveSizeBytes: 67339791,
    sha256: '29c62a69788b0533ef3ce1488eea1e1a90d6f7a0a7ece2a3ae7aadc78bd043e7',
    localDirectoryName: 'en_GB-alan-medium',
    modelFileName: 'en_GB-alan-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_GB-cori-medium',
    voiceId: 'en_GB-cori-medium',
    displayName: 'Cori',
    accent: TtsAccent.uk,
    isFemale: true,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_GB-cori-medium.tar.gz',
    archiveSizeBytes: 67431659,
    sha256: 'd49b0cc0353ceabc8cb15a4781b7c4f5cb858ecad52fbfb5591b2577b21b77e8',
    localDirectoryName: 'en_GB-cori-medium',
    modelFileName: 'en_GB-cori-medium.onnx',
  ),
  PiperVoiceMetadata(
    id: 'piper-en_GB-alba-medium',
    voiceId: 'en_GB-alba-medium',
    displayName: 'Alba',
    accent: TtsAccent.uk,
    isFemale: true,
    downloadUrl:
        '$_ttsCdnBaseUrl/model/tts/vits-piper-en_GB-alba-medium.tar.gz',
    archiveSizeBytes: 67356380,
    sha256: '3f2685f7c34ec9e025a05297e294a7dad0e373acefd4a796d872e7cee1e8a696',
    localDirectoryName: 'en_GB-alba-medium',
    modelFileName: 'en_GB-alba-medium.onnx',
  ),
];

/// 按 Piper 音色 ID 查询模型元数据。
PiperVoiceMetadata? piperTtsModelById(String id) {
  for (final model in piperTtsModelCatalog) {
    if (model.id == id) return model;
  }
  return null;
}

/// 按兼容音色 ID 查询模型元数据。
PiperVoiceMetadata? piperTtsVoiceById(String voiceId) {
  for (final model in piperTtsModelCatalog) {
    if (model.voiceId == voiceId) return model;
  }
  return null;
}

/// 返回指定口音的 Piper 模型（不可变视图）。
List<PiperVoiceMetadata> piperTtsModelsByAccent(TtsAccent accent) =>
    piperTtsModelCatalog
        .where((model) => model.accent == accent)
        .toList(growable: false);

/// 返回指定口音的默认 Piper 音色。
///
/// 默认值直接引用目录中的条目，避免设置、Provider 各自维护默认 ID。
PiperVoiceMetadata piperTtsDefaultVoice(TtsAccent accent) {
  final defaultId = switch (accent) {
    TtsAccent.us => piperTtsDefaultVoiceUsId,
    TtsAccent.uk => piperTtsDefaultVoiceUkId,
  };
  return piperTtsVoiceById(defaultId) ??
      (piperTtsModelsByAccent(accent).first);
}

/// Compatibility-friendly concise aliases for catalog consumers.
KokoroModelMetadata kokoroModelByVariant(KokoroModelVariant variant) =>
    kokoroTtsModelOf(variant);

PiperVoiceMetadata? piperVoiceById(String voiceId) =>
    piperTtsVoiceById(voiceId);

List<PiperVoiceMetadata> piperVoicesByAccent(TtsAccent accent) =>
    piperTtsModelsByAccent(accent);

PiperVoiceMetadata piperDefaultVoice(TtsAccent accent) =>
    piperTtsDefaultVoice(accent);

/// 按 Kokoro 变体查询模型元数据。
KokoroModelMetadata kokoroTtsModelOf(KokoroModelVariant variant) =>
    kokoroTtsModelCatalog[variant]!;
