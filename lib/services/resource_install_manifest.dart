import 'dart:convert';
import 'dart:io';

/// 可安装资源的通用安装清单 schema。
class ResourceInstallManifest {
  const ResourceInstallManifest({
    required this.resourceId,
    required this.installAt,
    required this.resourceSize,
  });

  final String resourceId;
  final DateTime installAt;
  final int resourceSize;

  /// 从 JSON 对象解析并校验安装清单字段类型和值。
  factory ResourceInstallManifest.fromJson(Map<String, dynamic> json) {
    final resourceId = json['resourceId'];
    final installAt = json['installAt'];
    final resourceSize = json['resourceSize'];
    if (resourceId is! String || resourceId.isEmpty) {
      throw const FormatException(
        'Invalid resource install manifest resourceId',
      );
    }
    if (installAt is! String) {
      throw const FormatException(
        'Invalid resource install manifest installAt',
      );
    }
    final parsedInstallAt = DateTime.tryParse(installAt);
    if (parsedInstallAt == null) {
      throw const FormatException(
        'Invalid resource install manifest installAt',
      );
    }
    if (resourceSize is! int || resourceSize < 0) {
      throw const FormatException(
        'Invalid resource install manifest resourceSize',
      );
    }
    return ResourceInstallManifest(
      resourceId: resourceId,
      installAt: parsedInstallAt,
      resourceSize: resourceSize,
    );
  }

  Map<String, dynamic> toJson() => {
    'resourceId': resourceId,
    'installAt': installAt.toIso8601String(),
    'resourceSize': resourceSize,
  };
}

/// 为已安装的资源写入统一格式的安装清单。
Future<void> writeResourceInstallManifest(
  Directory modelDirectory, {
  required String resourceId,
  required DateTime installAt,
}) async {
  final resourceSize = await calculateResourceSize(modelDirectory);
  final manifest = ResourceInstallManifest(
    resourceId: resourceId,
    installAt: installAt,
    resourceSize: resourceSize,
  );
  await File(
    '${modelDirectory.path}${Platform.pathSeparator}install.json',
  ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
}

/// 读取资源目录中的安装清单；目录或清单不存在时返回 null。
Future<ResourceInstallManifest?> readResourceInstallManifest(
  Directory resourceDirectory,
) async {
  final file = File(
    '${resourceDirectory.path}${Platform.pathSeparator}install.json',
  );
  if (!await file.exists()) return null;
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Invalid resource install manifest JSON');
  }
  return ResourceInstallManifest.fromJson(Map<String, dynamic>.from(decoded));
}

/// 计算资源目录内所有文件的总大小，单位为字节。
Future<int> calculateResourceSize(Directory modelDirectory) async {
  var total = 0;
  await for (final entity in modelDirectory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) total += await entity.length();
  }
  return total;
}
