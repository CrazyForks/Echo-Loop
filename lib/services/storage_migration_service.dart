import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Documents → Application Support 一次性数据迁移。
///
/// iOS 会在「设置 > 存储」中展示 Documents 目录的内容，导致用户看到
/// 数据库和字幕等内部文件。此迁移将所有用户数据移至 Application Support，
/// 该目录不会暴露给用户但仍会被 iCloud 备份。
///
/// 必须在数据库初始化之前调用。迁移是幂等的：中断后下次启动自动重试。
Future<void> migrateToAppSupportDirectory() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final appSupportDir = await getApplicationSupportDirectory();

  // 确保目标目录存在
  if (!appSupportDir.existsSync()) {
    await appSupportDir.create(recursive: true);
  }

  // 迁移数据库文件（含 WAL / SHM 伴随文件）
  for (final name in _dbFiles) {
    await _migrateFile(docsDir.path, appSupportDir.path, name);
  }

  // 迁移媒体目录
  for (final name in _mediaDirs) {
    await _migrateDirectory(docsDir.path, appSupportDir.path, name);
  }
}

/// 需要迁移的数据库相关文件。
const _dbFiles = [
  // 当前版本
  'echo_loop.db',
  'echo_loop.db-wal',
  'echo_loop.db-shm',
  'echo_loop_demo.db',
  'echo_loop_demo.db-wal',
  'echo_loop_demo.db-shm',
  // 旧版本名称（fluency → echo_loop 重命名迁移已删除，这里兜底）
  'fluency.db',
  'fluency.db-wal',
  'fluency.db-shm',
  'fluency_demo.db',
  'fluency_demo.db-wal',
  'fluency_demo.db-shm',
];

/// 需要迁移的媒体目录。
const _mediaDirs = ['audios', 'transcripts', 'demo'];

/// 将单个文件从 [srcRoot] 移动到 [dstRoot]（同名）。
///
/// 仅在源存在且目标不存在时执行，保证幂等。
Future<void> _migrateFile(String srcRoot, String dstRoot, String name) async {
  final src = File(p.join(srcRoot, name));
  final dst = File(p.join(dstRoot, name));
  if (await src.exists() && !await dst.exists()) {
    await src.rename(dst.path);
  }
}

/// 将目录从 [srcRoot] 移动到 [dstRoot]（同名）。
///
/// 仅在源存在且目标不存在时执行，保证幂等。
Future<void> _migrateDirectory(
  String srcRoot,
  String dstRoot,
  String name,
) async {
  final src = Directory(p.join(srcRoot, name));
  final dst = Directory(p.join(dstRoot, name));
  if (await src.exists() && !await dst.exists()) {
    await src.rename(dst.path);
  }
}
