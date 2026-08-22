import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_namespaces.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_schedule.dart';
import 'package:echo_loop/features/memory_scheduler/domain/memory_subject_ref.dart';
import 'package:echo_loop/features/memory_scheduler/providers/memory_scheduler_providers.dart';
import 'package:echo_loop/providers/favorite_vocabulary_lifecycle_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('取消与恢复收藏词汇会同步归档和恢复既有调度', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await db.savedWordDao.saveWord(word: 'stadium');
    final word = await db.savedWordDao.getByWord('stadium');
    final subject = MemorySubjectRef(
      namespace: kSavedWordOrPhraseNamespace,
      subjectId: word!.memorySubjectId!,
    );
    final lifecycle = container.read(favoriteVocabularyLifecycleProvider);
    final scheduler = container.read(memorySchedulerProvider);
    await lifecycle.restoreWordSchedule('stadium');

    expect(
      (await scheduler.getSchedule(subject))!.status,
      MemoryScheduleStatus.active,
    );

    await lifecycle.removeWord('stadium');

    expect((await db.savedWordDao.getByWord('stadium'))!.deletedAt, isNotNull);
    expect(
      (await scheduler.getSchedule(subject))!.status,
      MemoryScheduleStatus.archived,
    );

    await lifecycle.restoreWord('stadium');

    expect((await db.savedWordDao.getByWord('stadium'))!.deletedAt, isNull);
    expect(
      (await scheduler.getSchedule(subject))!.status,
      MemoryScheduleStatus.active,
    );
  });
}
