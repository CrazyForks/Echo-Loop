import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/features/official_collections/data/official_collection_api.dart';
import 'package:echo_loop/features/official_collections/download/download_progress.dart';
import 'package:echo_loop/features/official_collections/download/official_download_notifier.dart';
import 'package:echo_loop/features/official_collections/models/audio_content_dto.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/models/audio_item.dart' as model;
import 'package:echo_loop/models/word_timestamp.dart';
import 'package:echo_loop/providers/listening_practice/listening_practice_provider.dart';
import 'package:echo_loop/services/subtitle_parser.dart';
import 'package:echo_loop/utils/app_data_dir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mock_providers.dart';

class _FakeOfficialCollectionApi extends OfficialCollectionApi {
  AudioContent? nextContent;
  int callCount = 0;

  _FakeOfficialCollectionApi() : super.withDio(Dio());

  @override
  Future<AudioContent> getAudioContent(
    String remoteAudioId, {
    CancelToken? cancelToken,
  }) async {
    callCount++;
    return nextContent ??
        const AudioContent(
          audioUrl: 'https://example.com/audio.m4a',
          srt: '1\n00:00:00,000 --> 00:00:01,000\nhello\n',
          wordTimestamps: [],
        );
  }
}

class _TrackingListeningPractice extends TestListeningPractice {
  int loadCallCount = 0;
  bool? lastForceTranscriptReload;

  _TrackingListeningPractice(super.initialState);

  @override
  Future<void> loadAudio(
    model.AudioItem audioItem, {
    bool forceTranscriptReload = false,
  }) async {
    loadCallCount++;
    lastForceTranscriptReload = forceTranscriptReload;
  }
}

/// 只测 start() 的纯逻辑分支（busy / alreadyDownloaded）。
///
/// 完整下载流程涉及真实 Dio + 文件系统 + API，在单测中不可靠且无价值；
/// 端到端走 integration test + 手动 E2E 验证。
void main() {
  late AppDatabase db;
  late Directory tmpDir;
  late ProviderContainer container;
  late _FakeOfficialCollectionApi fakeApi;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('official_download_test_');
    appDataDirectoryOverride = tmpDir;
    db = AppDatabase(NativeDatabase.memory());
    initAppDatabase(db);
    fakeApi = _FakeOfficialCollectionApi();
    container = ProviderContainer(
      overrides: [officialCollectionApiProvider.overrideWithValue(fakeApi)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    appDataDirectoryOverride = null;
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  Future<void> seedAudio(
    String id, {
    String? remoteAudioId,
    bool downloaded = false,
  }) async {
    await db.audioItemDao.upsert(
      AudioItemsCompanion(
        id: Value(id),
        name: const Value('Track'),
        audioPath: downloaded
            ? const Value<String?>('audios/official/sha.m4a')
            : const Value<String?>(null),
        transcriptPath: downloaded
            ? const Value<String?>('transcripts/official_x.srt')
            : const Value<String?>(null),
        addedDate: Value(DateTime(2026, 4, 19)),
        updatedAt: Value(DateTime(2026, 4, 19)),
        remoteAudioId: Value(remoteAudioId),
        audioSha256: const Value('sha'),
      ),
    );
  }

  test('audio 已下载 → alreadyDownloaded，不启动任务', () async {
    await seedAudio('a1', remoteAudioId: 'r1', downloaded: true);
    final result = await container
        .read(officialDownloadProvider.notifier)
        .start(audioItemId: 'a1', displayName: 'Track 1');
    expect(result, StartResult.alreadyDownloaded);
    expect(container.read(officialDownloadProvider), isA<DownloadIdle>());
  });

  test('audio 不存在（remoteAudioId=null） → alreadyDownloaded', () async {
    await seedAudio('a2', remoteAudioId: null, downloaded: false);
    final result = await container
        .read(officialDownloadProvider.notifier)
        .start(audioItemId: 'a2', displayName: 'Track 2');
    expect(result, StartResult.alreadyDownloaded);
  });

  test('audioItemId 在 DB 不存在 → alreadyDownloaded（防御性，调用端可忽略）', () async {
    final result = await container
        .read(officialDownloadProvider.notifier)
        .start(audioItemId: 'missing', displayName: 'x');
    expect(result, StartResult.alreadyDownloaded);
  });

  test('并发约束：已有任务在跑 → busy', () async {
    await seedAudio('a1', remoteAudioId: 'r1');
    await seedAudio('a2', remoteAudioId: 'r2');

    // 手动把 state 设为 InProgress，模拟前一个任务正在跑
    final notifier = container.read(officialDownloadProvider.notifier);
    notifier.state = const DownloadInProgress(
      audioItemId: 'a1',
      displayName: 'Track 1',
      progress: 0.3,
    );

    final result = await notifier.start(
      audioItemId: 'a2',
      displayName: 'Track 2',
    );
    expect(result, StartResult.busy);
    // state 不变：仍是 a1 的 InProgress
    final s = container.read(officialDownloadProvider) as DownloadInProgress;
    expect(s.audioItemId, 'a1');
  });

  test('cancel 将 state 切回 Idle（即使没有活跃任务也幂等）', () async {
    final notifier = container.read(officialDownloadProvider.notifier);
    notifier.state = const DownloadInProgress(
      audioItemId: 'a1',
      displayName: 'Track 1',
      progress: 0.5,
    );
    await notifier.cancel();
    expect(container.read(officialDownloadProvider), isA<DownloadIdle>());

    // 再次 cancel 不抛
    await notifier.cancel();
    expect(container.read(officialDownloadProvider), isA<DownloadIdle>());
  });

  test('activeAudioItemId 反映当前 InProgress 的 audioItemId', () async {
    final notifier = container.read(officialDownloadProvider.notifier);
    expect(notifier.activeAudioItemId, isNull);
    notifier.state = const DownloadInProgress(
      audioItemId: 'a1',
      displayName: 'x',
      progress: 0,
    );
    expect(notifier.activeAudioItemId, 'a1');
  });

  test('updateTranscript 覆盖句子/词级字幕，并清空收藏句子和学习进度', () async {
    await seedAudio('a1', remoteAudioId: 'r1', downloaded: true);
    await db.bookmarkDao.addBookmark(
      BookmarksCompanion.insert(
        audioItemId: 'a1',
        sentenceIndex: 0,
        sentenceText: 'old subtitle',
        startTime: 0,
        endTime: 1,
        createdAt: DateTime(2026, 4, 20),
        updatedAt: DateTime(2026, 4, 20),
      ),
    );
    await db.learningProgressDao.upsert(
      LearningProgressesCompanion(
        audioItemId: const Value('a1'),
        totalStudyDurationMs: const Value(12345),
        updatedAt: Value(DateTime(2026, 4, 20)),
      ),
    );
    fakeApi.nextContent = const AudioContent(
      audioUrl: 'https://example.com/new-audio.m4a',
      srt: '1\n00:00:00,000 --> 00:00:01,000\nnew subtitle\n',
      wordTimestamps: [
        WordTimestamp(
          word: 'new',
          startTime: Duration.zero,
          endTime: Duration(milliseconds: 500),
        ),
      ],
    );

    final result = await container
        .read(officialDownloadProvider.notifier)
        .updateTranscript(audioItemId: 'a1');

    expect(result, SubtitleUpdateResult.updated);
    expect(fakeApi.callCount, 1);
    // 字幕内容写入 DB transcript_srt 列，transcriptPath 置 null（不再落文件）
    final srt = await db.audioItemDao.getTranscriptSrt('a1');
    expect(srt, contains('new subtitle'));
    final sentences = await SubtitleParser.parseSubtitleString(srt!);
    expect(sentences, hasLength(1));
    expect(sentences.single.text, 'new subtitle');

    final row = await db.audioItemDao.getById('a1');
    expect(row?.transcriptPath, isNull);
    expect(row?.wordTimestampsJson, contains('"word":"new"'));
    // 字幕统计随更新一起入库，避免学习计划页只显示时长
    expect(row?.sentenceCount, 1);
    expect(row?.wordCount, 2);

    final progress = await db.learningProgressDao.getByAudioId('a1');
    expect(progress, isNull);
    expect(await db.bookmarkDao.getByAudioId('a1'), isEmpty);
  });

  test('updateTranscript 更新当前音频时强制重载学习会话', () async {
    container.dispose();
    final tracking = _TrackingListeningPractice(
      ListeningPracticeState(
        currentAudioItem: model.AudioItem(
          id: 'a1',
          name: 'Track',
          audioPath: 'audios/official/sha.m4a',
          transcriptPath: 'transcripts/official_x.srt',
          addedDate: DateTime(2026, 4, 19),
          remoteAudioId: 'r1',
        ),
      ),
    );
    container = ProviderContainer(
      overrides: [
        officialCollectionApiProvider.overrideWithValue(fakeApi),
        listeningPracticeProvider.overrideWith(() => tracking),
      ],
    );
    await seedAudio('a1', remoteAudioId: 'r1', downloaded: true);
    container.read(listeningPracticeProvider);

    final result = await container
        .read(officialDownloadProvider.notifier)
        .updateTranscript(audioItemId: 'a1');

    expect(result, SubtitleUpdateResult.updated);
    expect(tracking.loadCallCount, 1);
    expect(tracking.lastForceTranscriptReload, isTrue);
  });
}
