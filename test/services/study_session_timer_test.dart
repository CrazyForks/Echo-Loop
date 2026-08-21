import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/models/study_stage.dart';
import 'package:echo_loop/services/study_session_timer.dart';
import 'package:echo_loop/services/study_time_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('stop persists foreground duration under the requested stage', () async {
    final timer = StudySessionTimer(
      studyTimeService: StudyTimeService(
        db.dailyStudyRecordDao,
        db.dailyStageStudyRecordDao,
      ),
      stage: StudyStage.savedSentencesReview,
    );

    timer.start();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await timer.stop();

    final records = await db.dailyStageStudyRecordDao.getByDate(DateTime.now());
    final record = records.singleWhere(
      (item) => item.stage == StudyStage.savedSentencesReview,
    );
    expect(record.studyTimeSeconds, greaterThanOrEqualTo(1));
    await timer.dispose();
  });
}
