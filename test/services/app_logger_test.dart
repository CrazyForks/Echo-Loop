/// AppLogger 持久化日志测试。
library;

import 'dart:io';

import 'package:echo_loop/services/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late String logDirectory;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('app_logger_test');
    logDirectory = '${tempDir.path}/logs';
    AppLogger.instance.clear();
  });

  tearDown(() async {
    await AppLogger.resetPersistentOutputForTesting();
    AppLogger.instance.clear();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('配置持久化输出后写入活动日志，且不恢复历史内存日志', () async {
    final directory = Directory(logDirectory)..createSync(recursive: true);
    File(
      '${directory.path}/app.log',
    ).writeAsStringSync('12:00:00.000 [Persisted] previous run\n');

    await AppLogger.configurePersistentOutput(logDirectory);

    expect(AppLogger.instance.entries, isEmpty);
    AppLogger.log('Test', 'hello world');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final persisted = await AppLogger.readPersistedLog();
    expect(persisted, contains('[Persisted] previous run'));
    expect(persisted, contains('[Test] hello world'));
  });

  test('formatLine 输出 HH:MM:SS.mmm [tag] message 格式', () {
    final line = AppLogger.formatLine(
      DateTime(2026, 6, 10, 9, 8, 7, 123),
      'ASREngine',
      'decode done',
    );
    expect(line, '09:08:07.123 [ASREngine] decode done');
  });

  test('读取持久化日志时按归档到活动文件的顺序拼接', () async {
    final directory = Directory(logDirectory)..createSync(recursive: true);
    File('${directory.path}/app-2026-01-01.log').writeAsStringSync('old\n');
    File('${directory.path}/app.log').writeAsStringSync('new\n');
    await AppLogger.configurePersistentOutput(logDirectory);

    expect(await AppLogger.readPersistedLog(), 'old\nnew\n');
  });

  test('清空操作同时删除活动与历史日志', () async {
    await AppLogger.configurePersistentOutput(logDirectory);
    AppLogger.log('Test', 'to clear');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await AppLogger.clearPersistedLogs();

    expect(AppLogger.instance.entries, isEmpty);
    final files = Directory(logDirectory).listSync().whereType<File>().toList();
    // 清空后会立即恢复轮转输出，因此只留下新的空活动文件。
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('/app.log'));
    expect(files.single.readAsStringSync(), isEmpty);
  });
}
