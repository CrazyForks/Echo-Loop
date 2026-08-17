import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_data_dir.dart';

import '../database/app_database.dart';
import 'app_logger.dart';

/// 内置示例内容安装器
///
/// 首次启动时将 assets/demo/ 中的示例音频复制到 Documents 目录，
/// 并在数据库中创建带有句子级、词级预置字幕的 "Examples" 合集。
/// 通过持久化标记确保每位用户最多安装一次，避免恢复用户主动删除的示例。
class BundledExampleInstaller {
  static const _installedKey = 'bundled_example_installed';

  /// 固定合集 ID（保证幂等）
  static const collectionId = 'bundled-example-collection-0001';

  static const _examples = <_BundledExample>[
    _BundledExample(
      id: 'bundled-example-audio-a1',
      title: 'A1 - Class Information',
      assetPath: 'assets/demo/A1 - Class Information.m4a',
      audioRelPath: 'audios/A1 - Class Information.m4a',
      durationSeconds: 32,
      sentenceCount: 7,
      wordCount: 56,
    ),
    _BundledExample(
      id: 'bundled-example-audio-a2',
      title: 'A2 - Change a meeting time',
      assetPath: 'assets/demo/A2 - Change a meeting time.m4a',
      audioRelPath: 'audios/A2 - Change a meeting time.m4a',
      durationSeconds: 36,
      sentenceCount: 11,
      wordCount: 91,
    ),
    _BundledExample(
      id: 'bundled-example-audio-b1',
      title: 'B1 - Work-life balance',
      assetPath: 'assets/demo/B1 - Work-life balance.m4a',
      audioRelPath: 'audios/B1 - Work-life balance.m4a',
      durationSeconds: 37,
      sentenceCount: 6,
      wordCount: 84,
    ),
    _BundledExample(
      id: 'bundled-example-audio-b2',
      title: 'B2 - Incentives',
      assetPath: 'assets/demo/B2 - Incentives.m4a',
      audioRelPath: 'audios/B2 - Incentives.m4a',
      durationSeconds: 38,
      sentenceCount: 5,
      wordCount: 83,
    ),
    _BundledExample(
      id: 'bundled-example-audio-c1',
      title: 'C1 - Rent a house',
      assetPath: 'assets/demo/C1 - Rent a house.m4a',
      audioRelPath: 'audios/C1 - Rent a house.m4a',
      durationSeconds: 37,
      sentenceCount: 5,
      wordCount: 110,
    ),
    _BundledExample(
      id: 'bundled-example-audio-c2',
      title: 'C2 - Conducting yourself',
      assetPath: 'assets/demo/C2 - Conducting yourself.m4a',
      audioRelPath: 'audios/C2 - Conducting yourself.m4a',
      durationSeconds: 42,
      sentenceCount: 6,
      wordCount: 125,
    ),
  ];

  final AppDatabase db;
  final SharedPreferences prefs;
  final AssetBundle assetBundle;

  BundledExampleInstaller(this.db, this.prefs, {AssetBundle? assetBundle})
    : assetBundle = assetBundle ?? rootBundle;

  /// 仅为首次空库用户安装示例内容，每位用户最多执行一次。
  Future<void> installOnFirstLaunch() async {
    if (prefs.getBool(_installedKey) ?? false) {
      AppLogger.log('BundledExamples', '安装跳过：此前已处理');
      return;
    }

    final existing = await (db.select(db.audioItems)..limit(1)).get();
    if (existing.isNotEmpty) {
      await prefs.setBool(_installedKey, true);
      AppLogger.log('BundledExamples', '安装跳过：已有用户音频，已标记为完成');
      return;
    }

    await _copyAssetFiles();
    final transcriptContents = await _loadTranscriptContents();
    await db.transaction(() async {
      await _insertDatabaseRecords(transcriptContents);
    });
    await prefs.setBool(_installedKey, true);
    AppLogger.log('BundledExamples', '安装完成：${_examples.length} 条示例已写入');
  }

  /// 将 asset 文件复制到应用数据目录
  Future<void> _copyAssetFiles() async {
    final docsDir = await getAppDataDirectory();
    final audiosDir = Directory(p.join(docsDir.path, 'audios'));
    if (!audiosDir.existsSync()) {
      await audiosDir.create(recursive: true);
    }

    for (final example in _examples) {
      final audioData = await assetBundle.load(example.assetPath);
      final audioFile = File(p.join(docsDir.path, example.audioRelPath));
      await audioFile.writeAsBytes(
        audioData.buffer.asUint8List(
          audioData.offsetInBytes,
          audioData.lengthInBytes,
        ),
        flush: true,
      );
    }
  }

  /// 读取随安装包发布的字幕，数据库才是运行时字幕的唯一真相源。
  Future<Map<String, _BundledTranscriptContent>>
  _loadTranscriptContents() async {
    final contents = <String, _BundledTranscriptContent>{};
    for (final example in _examples) {
      final basePath = example.assetPath.substring(
        0,
        example.assetPath.length - '.m4a'.length,
      );
      contents[example.id] = _BundledTranscriptContent(
        srt: await assetBundle.loadString('$basePath.srt'),
        wordTimestampsJson: await assetBundle.loadString(
          '$basePath.words.json',
        ),
      );
    }
    return contents;
  }

  /// 在数据库中创建合集和音频条目
  Future<void> _insertDatabaseRecords(
    Map<String, _BundledTranscriptContent> transcriptContents,
  ) async {
    final now = DateTime.now();

    // 创建或恢复 "Examples" 合集
    await db
        .into(db.collections)
        .insertOnConflictUpdate(
          CollectionsCompanion.insert(
            id: collectionId,
            name: 'Examples',
            createdDate: now,
            updatedAt: now,
            deletedAt: const Value(null),
          ),
        );

    for (var i = 0; i < _examples.length; i++) {
      final example = _examples[i];
      final transcriptContent = transcriptContents[example.id];
      if (transcriptContent == null) {
        throw StateError('缺少内置示例字幕: ${example.id}');
      }
      // 新条目直接写入随安装包发布的完整字幕，用户无需先转录。
      await db
          .into(db.audioItems)
          .insert(
            AudioItemsCompanion.insert(
              id: example.id,
              name: example.title,
              audioPath: Value(example.audioRelPath),
              addedDate: now,
              totalDuration: Value(example.durationSeconds),
              sentenceCount: Value(example.sentenceCount),
              wordCount: Value(example.wordCount),
              transcriptSource: const Value(1),
              transcriptLanguage: const Value('en'),
              transcriptSrt: Value(transcriptContent.srt),
              wordTimestampsJson: Value(transcriptContent.wordTimestampsJson),
              updatedAt: now,
            ),
          );

      // 关联音频到合集
      await db
          .into(db.collectionAudioItems)
          .insertOnConflictUpdate(
            CollectionAudioItemsCompanion.insert(
              collectionId: collectionId,
              audioItemId: example.id,
              sortOrder: Value(i),
              addedAt: now,
            ),
          );
    }
  }
}

class _BundledExample {
  final String id;
  final String title;
  final String assetPath;
  final String audioRelPath;
  final int durationSeconds;
  final int sentenceCount;
  final int wordCount;

  const _BundledExample({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.audioRelPath,
    required this.durationSeconds,
    required this.sentenceCount,
    required this.wordCount,
  });
}

class _BundledTranscriptContent {
  final String srt;
  final String wordTimestampsJson;

  const _BundledTranscriptContent({
    required this.srt,
    required this.wordTimestampsJson,
  });
}
