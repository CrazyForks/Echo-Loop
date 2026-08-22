import 'package:echo_loop/features/scheduled_flashcard/domain/review_session_summary.dart';
import 'package:echo_loop/theme/app_theme.dart';
import 'package:echo_loop/widgets/review/review_completion_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows celebration, summary metrics, and all rating proportions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ReviewCompletionSummary(
              title: '收藏句复习已完成',
              summary: ReviewSessionSummary(
                elapsed: Duration(minutes: 2, seconds: 8),
                reviewedCount: 2,
                againCount: 1,
                goodCount: 1,
                easyCount: 1,
              ),
              durationLabel: '复习时长',
              reviewedLabel: '复习条数',
              retentionLabel: '保持率',
              ratingsLabel: '评分分布',
              againLabel: '听不懂',
              goodLabel: '听懂了',
              easyLabel: '轻松听懂',
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('review-completion-confetti')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('review-completion-title')), findsOneWidget);
      expect(find.text('收藏句复习已完成'), findsOneWidget);
      expect(find.text('2m 8s'), findsOneWidget);
      expect(find.text('66.7%'), findsOneWidget);
      expect(find.text('🧠'), findsOneWidget);
      expect(find.byKey(const Key('review-completion-again')), findsOneWidget);
      expect(find.byKey(const Key('review-completion-good')), findsOneWidget);
      expect(find.byKey(const Key('review-completion-easy')), findsOneWidget);
      expect(find.text('听不懂'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(3));
      expect(find.text('33.3%'), findsNWidgets(3));
    },
  );
}
