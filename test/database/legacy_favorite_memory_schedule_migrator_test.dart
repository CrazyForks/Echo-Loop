import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart' hide MemorySchedule;
import 'package:echo_loop/database/migration/legacy_favorite_memory_schedule_migrator.dart';
import 'package:echo_loop/features/memory_scheduler/adapters/fsrs/fsrs_memory_model_adapter.dart';
import 'package:echo_loop/features/memory_scheduler/application/default_memory_scheduler.dart';
import 'package:echo_loop/features/memory_scheduler/application/memory_model_registry.dart';
import 'package:echo_loop/features/memory_scheduler/application/memory_scheduler.dart';
import 'package:echo_loop/features/memory_scheduler/config/memory_profiles.dart';
import 'package:echo_loop/features/memory_scheduler/data/drift_memory_schedule_repository.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_namespaces.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_schedule.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_scheduler_commands.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_subject_ref.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:flutter_test/flutter_test.dart';

final _migratedAt = DateTime.utc(2026, 8, 23, 12);

void main() {
  late AppDatabase database;
  late DefaultMemoryScheduler scheduler;
  late LegacyFavoriteMemoryScheduleMigrator migrator;

  setUp(() async {
    database = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    scheduler = DefaultMemoryScheduler(
      repository: DriftMemoryScheduleRepository(database),
      profileRegistry: kMemoryProfileRegistry,
      modelRegistry: StaticMemoryModelRegistry(<FsrsMemoryModelAdapter>[
        FsrsMemoryModelAdapter(),
      ]),
      idGenerator: _TestIdGenerator(),
      clock: Clock.fixed(_migratedAt),
    );
    migrator = LegacyFavoriteMemoryScheduleMigrator(
      database: database,
      scheduler: scheduler,
      clock: Clock.fixed(_migratedAt),
    );
    await database.audioItemDao.upsert(
      AudioItemsCompanion(
        id: const Value('audio-1'),
        name: const Value('Audio one'),
        addedDate: Value(_migratedAt),
        updatedAt: Value(_migratedAt),
      ),
    );
  });

  tearDown(() => database.close());

  test('有效活跃旧收藏创建立即到期的 FSRS newItem 快照', () async {
    await _insertBookmark(database, subjectId: 'sentence-1');
    await database.savedWordDao.saveWord(word: 'apple');
    await database.savedSenseGroupDao.saveSenseGroup(
      phraseText: 'look up',
      displayText: 'look up',
    );

    final report = await migrator.migrate();
    final schedules = await database.select(database.memorySchedules).get();

    expect(report.activeSchedulesCreated, 3);
    expect(schedules, hasLength(3));
    for (final schedule in schedules) {
      expect(schedule.status, MemoryScheduleStatus.active.name);
      expect(schedule.phase, MemorySchedulePhase.newItem.name);
      expect(schedule.dueAt.toUtc(), _migratedAt);
      expect(schedule.reviewCount, 0);
      expect(schedule.profileId, kFsrsDefaultProfileRef.profileId);
      expect(schedule.profileVersion, kFsrsDefaultProfileRef.profileVersion);
    }
    expect(
      await scheduler.getDueCount(
        DueMemoryCountQuery(
          namespaces: {
            kSavedSentenceNamespace,
            kSavedWordOrPhraseNamespace,
            kSavedSenseGroupNamespace,
          },
          phases: null,
          dueBeforeOrAt: _migratedAt,
        ),
      ),
      3,
    );
  });

  test('回收站收藏创建 archived 快照并修复 active 状态', () async {
    await _insertBookmark(database, subjectId: 'sentence-deleted');
    await database.savedWordDao.saveWord(word: 'removed');
    await database.savedWordDao.removeWord('removed');
    await database.savedSenseGroupDao.saveSenseGroup(
      phraseText: 'removed group',
      displayText: 'removed group',
    );
    await database.savedSenseGroupDao.removeSenseGroup('removed group');
    await _ensure(scheduler, 'sentence-deleted', kSavedSentenceNamespace);
    await _ensure(scheduler, 'word-active', kSavedWordOrPhraseNamespace);
    await (database.update(
      database.savedWords,
    )..where((table) => table.word.equals('removed'))).write(
      const SavedWordsCompanion(memorySubjectId: Value('word-active')),
    );

    await (database.update(database.bookmarks)
          ..where((table) => table.memorySubjectId.equals('sentence-deleted')))
        .write(BookmarksCompanion(deletedAt: Value(_migratedAt)));

    await migrator.migrate();

    expect(
      (await _schedule(
        scheduler,
        'sentence-deleted',
        kSavedSentenceNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
    final archivedGroup =
        (await database.select(database.savedSenseGroups).get()).singleWhere(
          (group) => group.phraseText == 'removed group',
        );
    expect(
      (await _schedule(
        scheduler,
        archivedGroup.memorySubjectId!,
        kSavedSenseGroupNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
    expect(
      (await _schedule(
        scheduler,
        'word-active',
        kSavedWordOrPhraseNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
  });

  test('无效旧句子不会进入复习队列，已有 active 快照会归档', () async {
    await _insertBookmark(
      database,
      subjectId: 'invalid-sentence',
      sentenceText: ' ',
      startTime: 4,
      endTime: 4,
    );
    await _ensure(scheduler, 'invalid-sentence', kSavedSentenceNamespace);

    final report = await migrator.migrate();
    final schedule = await _schedule(
      scheduler,
      'invalid-sentence',
      kSavedSentenceNamespace,
    );

    expect(report.invalidSentencesSkipped, 1);
    expect(schedule?.status, MemoryScheduleStatus.archived);
    expect(
      await scheduler.getDueCount(
        DueMemoryCountQuery(
          namespaces: {kSavedSentenceNamespace},
          phases: null,
          dueBeforeOrAt: _migratedAt,
        ),
      ),
      0,
    );
  });

  test('所属音频已删除的旧收藏不会保留 active 调度', () async {
    await _insertBookmark(database, subjectId: 'hidden-audio-sentence');
    await _ensure(scheduler, 'hidden-audio-sentence', kSavedSentenceNamespace);
    await (database.update(database.audioItems)
          ..where((table) => table.id.equals('audio-1')))
        .write(AudioItemsCompanion(deletedAt: Value(_migratedAt)));

    final report = await migrator.migrate();

    expect(report.unavailableAudioBookmarksArchived, 1);
    expect(
      (await _schedule(
        scheduler,
        'hidden-audio-sentence',
        kSavedSentenceNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
  });

  test('无收藏源记录的 active 快照会归档且不再计入待复习', () async {
    await _ensure(scheduler, 'orphan-sentence', kSavedSentenceNamespace);

    final report = await migrator.migrate();

    expect(report.orphanSchedulesArchived, 1);
    expect(
      (await _schedule(
        scheduler,
        'orphan-sentence',
        kSavedSentenceNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
    expect(
      await scheduler.getDueCount(
        DueMemoryCountQuery(
          namespaces: {kSavedSentenceNamespace},
          phases: null,
          dueBeforeOrAt: _migratedAt,
        ),
      ),
      0,
    );
  });

  test('已有有效 FSRS 快照保留评分历史和到期时间', () async {
    await _insertBookmark(database, subjectId: 'reviewed-sentence');
    await _ensure(scheduler, 'reviewed-sentence', kSavedSentenceNamespace);
    final before = await scheduler.review(
      ReviewMemoryCommand(
        subject: MemorySubjectRef(
          namespace: kSavedSentenceNamespace,
          subjectId: 'reviewed-sentence',
        ),
        rating: MemoryRating.good,
        reviewedAt: _migratedAt,
        responseTime: const Duration(seconds: 1),
        operationId: 'reviewed-sentence-good',
        expectedRevision: 0,
      ),
    );

    final report = await migrator.migrate();
    final after = await _schedule(
      scheduler,
      'reviewed-sentence',
      kSavedSentenceNamespace,
    );

    expect(report.activeSchedulesCreated, 0);
    expect(after?.reviewCount, before.schedule.reviewCount);
    expect(after?.dueAt, before.schedule.dueAt);
    expect(after?.revision, before.schedule.revision);
  });

  test('软删除单词和意群会归档已有 active 快照', () async {
    await database.savedWordDao.saveWord(word: 'removed word');
    await database.savedSenseGroupDao.saveSenseGroup(
      phraseText: 'removed phrase',
      displayText: 'Removed phrase',
    );
    final word = (await database.savedWordDao.getByWord('removed word'))!;
    final group = (await database.savedSenseGroupDao.getByPhraseText(
      'removed phrase',
    ))!;
    await _ensure(
      scheduler,
      word.memorySubjectId!,
      kSavedWordOrPhraseNamespace,
    );
    await _ensure(scheduler, group.memorySubjectId!, kSavedSenseGroupNamespace);
    await database.savedWordDao.removeWord('removed word');
    await database.savedSenseGroupDao.removeSenseGroup('removed phrase');

    await migrator.migrate();

    expect(
      (await _schedule(
        scheduler,
        word.memorySubjectId!,
        kSavedWordOrPhraseNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
    expect(
      (await _schedule(
        scheduler,
        group.memorySubjectId!,
        kSavedSenseGroupNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
  });

  test('恢复中的单词和意群会恢复既有 archived 快照', () async {
    await database.savedWordDao.saveWord(word: 'restored word');
    await database.savedSenseGroupDao.saveSenseGroup(
      phraseText: 'restored phrase',
      displayText: 'Restored phrase',
    );
    final word = (await database.savedWordDao.getByWord('restored word'))!;
    final group = (await database.savedSenseGroupDao.getByPhraseText(
      'restored phrase',
    ))!;
    await _ensure(
      scheduler,
      word.memorySubjectId!,
      kSavedWordOrPhraseNamespace,
    );
    await _ensure(scheduler, group.memorySubjectId!, kSavedSenseGroupNamespace);
    await scheduler.archive(
      ArchiveMemoryScheduleCommand(
        subject: MemorySubjectRef(
          namespace: kSavedWordOrPhraseNamespace,
          subjectId: word.memorySubjectId!,
        ),
        archivedAt: _migratedAt,
        expectedRevision: 0,
      ),
    );
    await scheduler.archive(
      ArchiveMemoryScheduleCommand(
        subject: MemorySubjectRef(
          namespace: kSavedSenseGroupNamespace,
          subjectId: group.memorySubjectId!,
        ),
        archivedAt: _migratedAt,
        expectedRevision: 0,
      ),
    );

    final report = await migrator.migrate();

    expect(report.schedulesRestored, 2);
    expect(
      (await _schedule(
        scheduler,
        word.memorySubjectId!,
        kSavedWordOrPhraseNamespace,
      ))?.status,
      MemoryScheduleStatus.active,
    );
    expect(
      (await _schedule(
        scheduler,
        group.memorySubjectId!,
        kSavedSenseGroupNamespace,
      ))?.status,
      MemoryScheduleStatus.active,
    );
  });

  test('无源单词和意群 active 快照会归档', () async {
    await _ensure(scheduler, 'orphan-word', kSavedWordOrPhraseNamespace);
    await _ensure(scheduler, 'orphan-group', kSavedSenseGroupNamespace);

    final report = await migrator.migrate();

    expect(report.orphanSchedulesArchived, 2);
    expect(
      (await _schedule(
        scheduler,
        'orphan-word',
        kSavedWordOrPhraseNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
    expect(
      (await _schedule(
        scheduler,
        'orphan-group',
        kSavedSenseGroupNamespace,
      ))?.status,
      MemoryScheduleStatus.archived,
    );
  });

  test('补齐缺失主体 ID 且重复运行不会重建快照或事件', () async {
    await _insertBookmark(database, subjectId: '');

    final first = await migrator.migrate();
    final bookmark = (await database.select(database.bookmarks).get()).single;
    final firstSchedules = await database
        .select(database.memorySchedules)
        .get();
    final second = await migrator.migrate();
    final secondSchedules = await database
        .select(database.memorySchedules)
        .get();
    final events = await database.select(database.memoryReviewEvents).get();

    expect(first.subjectIdsBackfilled, 1);
    expect(bookmark.memorySubjectId, isNotEmpty);
    expect(firstSchedules, hasLength(1));
    expect(second.activeSchedulesCreated, 0);
    expect(secondSchedules, hasLength(1));
    expect(events, isEmpty);
  });
}

Future<void> _insertBookmark(
  AppDatabase database, {
  required String subjectId,
  String sentenceText = 'A valid sentence.',
  double startTime = 0,
  double endTime = 3,
}) => database
    .into(database.bookmarks)
    .insert(
      BookmarksCompanion.insert(
        memorySubjectId: Value(subjectId),
        audioItemId: 'audio-1',
        sentenceIndex: subjectId.hashCode,
        sentenceText: sentenceText,
        startTime: startTime,
        endTime: endTime,
        createdAt: _migratedAt,
        updatedAt: _migratedAt,
      ),
    );

Future<void> _ensure(
  DefaultMemoryScheduler scheduler,
  String subjectId,
  String namespace,
) async {
  await scheduler.ensureSchedule(
    EnsureMemoryScheduleCommand(
      subject: MemorySubjectRef(namespace: namespace, subjectId: subjectId),
      profile: kFsrsDefaultProfileRef,
      occurredAt: _migratedAt,
    ),
  );
}

Future<MemorySchedule?> _schedule(
  DefaultMemoryScheduler scheduler,
  String subjectId,
  String namespace,
) => scheduler.getSchedule(
  MemorySubjectRef(namespace: namespace, subjectId: subjectId),
);

final class _TestIdGenerator implements MemoryIdGenerator {
  int _next = 0;

  @override
  String newId() => 'schedule-${_next++}';
}
