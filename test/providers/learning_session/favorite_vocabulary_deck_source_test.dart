import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart' hide MemorySchedule;
import 'package:echo_loop/features/memory_scheduler/adapters/fsrs/fsrs_memory_model_adapter.dart';
import 'package:echo_loop/features/memory_scheduler/application/default_memory_scheduler.dart';
import 'package:echo_loop/features/memory_scheduler/application/memory_model_registry.dart';
import 'package:echo_loop/features/memory_scheduler/application/memory_scheduler.dart';
import 'package:echo_loop/features/memory_scheduler/config/memory_profiles.dart';
import 'package:echo_loop/features/memory_scheduler/data/drift_memory_schedule_repository.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_rating.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_scheduler_commands.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_namespaces.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_subject_ref.dart';
import 'package:echo_loop/models/favorite_review_settings.dart';
import 'package:echo_loop/providers/learning_session/favorite_vocabulary_deck_source.dart';
import 'package:echo_loop/providers/learning_session/favorite_review_deck_source.dart';
import 'package:flutter_test/flutter_test.dart';

SavedWord _word(String memorySubjectId, String text, {DateTime? createdAt}) =>
    SavedWord(
      id: memorySubjectId.hashCode,
      word: text,
      memorySubjectId: memorySubjectId,
      practiceCount: 0,
      totalStudyMs: 0,
      viewedBack: false,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      updatedAt: createdAt ?? DateTime.utc(2026, 1, 1),
      syncStatus: 0,
    );

SavedSenseGroup _phrase(
  String memorySubjectId,
  String text, {
  DateTime? createdAt,
}) => SavedSenseGroup(
  id: memorySubjectId.hashCode,
  phraseText: text,
  memorySubjectId: memorySubjectId,
  displayText: text,
  practiceCount: 0,
  totalStudyMs: 0,
  viewedBack: false,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  updatedAt: createdAt ?? DateTime.utc(2026, 1, 1),
  syncStatus: 0,
);

void main() {
  late AppDatabase database;
  late MemoryScheduler scheduler;
  final now = DateTime.utc(2026, 8, 15, 8);

  setUp(() {
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
      idGenerator: _IncrementingIdGenerator(),
      clock: Clock.fixed(now),
    );
  });

  tearDown(() => database.close());

  FavoriteVocabularyDeckSource source({
    List<SavedWord> words = const [],
    List<SavedSenseGroup> phrases = const [],
    FavoriteReviewSettings settings = const FavoriteReviewSettings(),
  }) => FavoriteVocabularyDeckSource(
    words: words,
    phrases: phrases,
    scheduler: scheduler,
    settings: settings,
    now: () => now,
  );

  /// 让某个 subject 拥有一个到期时间在未来的既有 schedule。
  Future<void> pushDueIntoFuture(String namespace, String subjectId) async {
    final subject = MemorySubjectRef(
      namespace: namespace,
      subjectId: subjectId,
    );
    final schedule = await scheduler.ensureSchedule(
      EnsureMemoryScheduleCommand(
        subject: subject,
        profile: kFsrsDefaultProfileRef,
        occurredAt: now,
      ),
    );
    final preview = await scheduler.previewRatings(
      PreviewMemoryRatingsQuery(
        subject: subject,
        reviewedAt: now,
        expectedRevision: schedule.revision,
      ),
    );
    await scheduler.review(
      ReviewMemoryCommand(
        subject: subject,
        rating: MemoryRating.easy,
        preview: preview.easy,
        reviewedAt: now,
        responseTime: Duration.zero,
        operationId: 'seed-$subjectId',
        expectedRevision: schedule.revision,
      ),
    );
  }

  test('新卡立即到期，未到期的既有单词被过滤', () async {
    await pushDueIntoFuture(kSavedWordOrPhraseNamespace, 'future-word');
    final due = await source(
      words: [_word('future-word', 'apple'), _word('new-word', 'banana')],
    ).load();

    expect(due, hasLength(1));
    expect(due.single.subject.subjectId, 'new-word');
    expect(due.single.content.displayText, 'banana');
  });

  test('单词和意群合并进同一个队列', () async {
    final due = await source(
      words: [_word('w1', 'apple')],
      phrases: [_phrase('p1', 'give up')],
    ).load();

    expect(due.map((c) => c.subject.namespace).toSet(), {
      kSavedWordOrPhraseNamespace,
      kSavedSenseGroupNamespace,
    });
    expect(due.map((c) => c.content.displayText).toSet(), {'apple', 'give up'});
  });

  test('过滤非法项：空文本、缺失 memorySubjectId', () async {
    final due = await source(
      words: [
        _word('has-subject', 'valid'),
        SavedWord(
          id: 999,
          word: 'no-subject',
          practiceCount: 0,
          totalStudyMs: 0,
          viewedBack: false,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          syncStatus: 0,
        ),
      ],
      phrases: [_phrase('blank-text', '   ')],
    ).load();

    expect(due, hasLength(1));
    expect(due.single.subject.subjectId, 'has-subject');
  });

  test('dueAt 排序：dueAt 相同时按 namespace:subjectId 稳定排序', () async {
    final due = await source(
      words: [_word('earlier', 'a')],
      phrases: [_phrase('also-new', 'b')],
      settings: const FavoriteReviewSettings(order: FavoriteReviewOrder.dueAt),
    ).load();

    // 两张都是新卡，dueAt 相同（都等于 now），退化为按 "namespace:subjectId"
    // 稳定排序；'saved_sense_group:...' 字典序早于 'saved_word_or_phrase:...'。
    expect(due.map((c) => c.subject.subjectId), ['also-new', 'earlier']);
  });

  test('无每日目标时返回所有到期单词和意群', () async {
    const settings = FavoriteReviewSettings();
    final words = [_word('first', 'a')];
    final phrases = [_phrase('second', 'b')];

    final firstLoad = await source(
      words: words,
      phrases: phrases,
      settings: settings,
    ).load();
    expect(firstLoad, hasLength(2));

    final secondLoad = await source(
      words: words,
      phrases: phrases,
      settings: settings,
    ).load();
    expect(secondLoad, hasLength(2));
  });

  test('通用 deck 返回所有到期内容', () async {
    const settings = FavoriteReviewSettings();
    final sentenceDeck = FavoriteReviewDeckSource<String>(
      items: [
        FavoriteReviewDeckItem(
          content: 'sentence',
          subject: MemorySubjectRef(
            namespace: kSavedSentenceNamespace,
            subjectId: 'sentence-1',
          ),
          createdAt: now,
        ),
      ],
      scheduler: scheduler,
      settings: settings,
      now: () => now,
    );

    expect(await sentenceDeck.load(), hasLength(1));
    final vocabulary = await source(
      words: [_word('word-1', 'apple')],
      settings: settings,
    ).load();
    expect(vocabulary, hasLength(1));
  });

  test('随机排序不丢卡也不重复', () async {
    final due = await source(
      words: [_word('r1', 'a'), _word('r2', 'b')],
      phrases: [_phrase('r3', 'c')],
      settings: const FavoriteReviewSettings(order: FavoriteReviewOrder.random),
    ).load();
    expect(due.map((c) => c.subject.subjectId).toSet(), {'r1', 'r2', 'r3'});
  });
}

final class _IncrementingIdGenerator implements MemoryIdGenerator {
  int _next = 0;
  @override
  String newId() => 'id-${++_next}';
}
