/// 复述 AI 评估弹窗的展示与失败态测试。
///
/// 覆盖：评级未到达时不渲染评级词、四种要点状态与统计条、空字段不占位、
/// 转录默认收起、失败态按错误码给文案并能重试。
library;

import 'dart:async';

import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/models/retell_review_evaluation.dart';
import 'package:echo_loop/providers/retell_review_evaluation_provider.dart';
import 'package:echo_loop/services/audio_playback_service.dart';
import 'package:echo_loop/theme/app_theme.dart';
import 'package:echo_loop/widgets/retell/retell_review_report.dart';
import 'package:echo_loop/widgets/retell/retell_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlaybackService extends Mock implements AudioPlaybackService {}

/// 直接把状态钉死，避免 widget 测试触碰真实网络与音频转码。
class _FixedReviewController extends RetellReviewEvaluationController {
  _FixedReviewController(this._fixedState);

  final RetellReviewEvaluationState _fixedState;

  @override
  RetellReviewEvaluationState build() => _fixedState;
}

void main() {
  late _MockPlaybackService playback;

  setUp(() {
    playback = _MockPlaybackService();
    when(() => playback.isPlaying).thenReturn(false);
    when(
      () => playback.isPlayingStream,
    ).thenAnswer((_) => const Stream<bool>.empty());
  });

  Widget wrap(Widget child, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );

  Widget report(
    RetellReviewEvaluation evaluation, {
    bool isStreaming = false,
  }) => Padding(
    padding: const EdgeInsets.all(16),
    child: RetellReviewReport(
      evaluation: evaluation,
      isStreaming: isStreaming,
      recordingPath: '/tmp/retell.m4a',
      playbackService: playback,
      onBeforePlayback: () async {},
    ),
  );

  testWidgets('评级未到达时显示评估中，不渲染任何评级词', (tester) async {
    await tester.pumpWidget(
      wrap(
        report(
          const RetellReviewEvaluation(summary: 'You covered the main idea.'),
          isStreaming: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Evaluating…'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
    expect(find.text('Excellent'), findsNothing);
    expect(find.text('Keep going'), findsNothing);
    // 流式未结束时提示后续还有内容。
    expect(find.text('Generating…'), findsOneWidget);
  });

  testWidgets('四种要点状态各有图标，统计条按状态计数', (tester) async {
    await tester.pumpWidget(
      wrap(
        report(
          const RetellReviewEvaluation(
            summary: 'Mostly accurate.',
            rating: RetellReviewRating.good,
            keyPoints: [
              RetellReviewKeyPoint(
                keyPoint: 'Practice improves fluency',
                status: RetellReviewKeyPointStatus.covered,
                feedback: '',
              ),
              RetellReviewKeyPoint(
                keyPoint: 'Feedback matters',
                status: RetellReviewKeyPointStatus.covered,
                feedback: '',
              ),
              RetellReviewKeyPoint(
                keyPoint: 'Sleep consolidates memory',
                status: RetellReviewKeyPointStatus.partial,
                feedback: 'Only half of it was said.',
              ),
              RetellReviewKeyPoint(
                keyPoint: 'Spacing beats cramming',
                status: RetellReviewKeyPointStatus.missed,
                feedback: 'Not mentioned at all.',
              ),
              RetellReviewKeyPoint(
                keyPoint: 'Cause and effect',
                status: RetellReviewKeyPointStatus.distorted,
                feedback: 'The direction was reversed.',
              ),
              // 文本未到达的半成品条目不渲染。
              RetellReviewKeyPoint(keyPoint: '', status: null, feedback: ''),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Key point coverage'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.contrast_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
    // 统计条：图标 + 色点各一套，色点行文案带计数。
    expect(find.text('2 Covered'), findsOneWidget);
    expect(find.text('1 Partial'), findsOneWidget);
    expect(find.text('1 Missed'), findsOneWidget);
    expect(find.text('1 Distorted'), findsOneWidget);
    expect(find.text('Only half of it was said.'), findsOneWidget);
    // 半成品条目被跳过，不会出现空行（5 条有效要点）。
    expect(find.text('Cause and effect'), findsOneWidget);
  });

  testWidgets('建议与表达纠错为空时不渲染对应区块', (tester) async {
    await tester.pumpWidget(
      wrap(
        report(
          const RetellReviewEvaluation(
            summary: 'Nice work.',
            rating: RetellReviewRating.perfect,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Perfect!'), findsOneWidget);
    expect(find.text('One suggestion'), findsNothing);
    expect(find.text('Expression corrections'), findsNothing);
    expect(find.byIcon(Icons.lightbulb_rounded), findsNothing);
  });

  testWidgets('表达纠错渲染类别标签、原句与更正，建议渲染为 callout', (tester) async {
    await tester.pumpWidget(
      wrap(
        report(
          const RetellReviewEvaluation(
            rating: RetellReviewRating.fair,
            suggestion: 'List three keywords before you start.',
            corrections: [
              RetellReviewCorrection(
                type: RetellReviewCorrectionType.grammar,
                transcript: "he don't know",
                correction: "he doesn't know",
                explanation: 'Third person singular takes doesn\'t.',
              ),
              // 原句未到达的半成品条目不渲染。
              RetellReviewCorrection(
                type: null,
                transcript: '',
                correction: '',
                explanation: '',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('One suggestion'), findsOneWidget);
    expect(find.text('List three keywords before you start.'), findsOneWidget);
    expect(find.text('Expression corrections'), findsOneWidget);
    expect(find.text('Grammar'), findsOneWidget);
    expect(find.text("he don't know"), findsOneWidget);
    expect(find.text("he doesn't know"), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_right_rounded), findsOneWidget);
  });

  testWidgets('只有语法和用词类别的原句划删除线', (tester) async {
    await tester.pumpWidget(
      wrap(
        report(
          const RetellReviewEvaluation(
            rating: RetellReviewRating.fair,
            corrections: [
              RetellReviewCorrection(
                type: RetellReviewCorrectionType.wordChoice,
                transcript: 'open the light',
                correction: 'turn on the light',
                explanation: 'Use turn on with a light.',
              ),
              RetellReviewCorrection(
                type: RetellReviewCorrectionType.redundancy,
                transcript: 'in my own personal opinion',
                correction: 'in my opinion',
                explanation: 'Own and personal repeat the same idea.',
              ),
              // 类别未到达时不渲染标签，也不划线。
              RetellReviewCorrection(
                type: null,
                transcript: 'and then and then',
                correction: '',
                explanation: '',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    TextDecoration? decorationOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.decoration;

    expect(decorationOf('open the light'), TextDecoration.lineThrough);
    expect(decorationOf('in my own personal opinion'), TextDecoration.none);
    expect(decorationOf('and then and then'), TextDecoration.none);
    expect(find.text('Word choice'), findsOneWidget);
    expect(find.text('Wordy'), findsOneWidget);
  });

  testWidgets('转录默认收起，点击标题后展开', (tester) async {
    const transcript = 'I practiced retelling the paragraph today.';
    await tester.pumpWidget(
      wrap(
        report(
          const RetellReviewEvaluation(
            transcript: transcript,
            rating: RetellReviewRating.good,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Transcription'), findsOneWidget);
    expect(find.text(transcript), findsNothing);

    await tester.tap(find.text('Transcription'));
    await tester.pumpAndSettle();

    expect(find.text(transcript), findsOneWidget);
  });

  testWidgets('失败态按错误码给文案，点击重试触发回调', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showRetellReviewSheet(
                context,
                recordingPath: '/tmp/retell.m4a',
                playbackService: playback,
                onBeforePlayback: () async {},
                onRetry: () async => retried++,
              ),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: [
          retellReviewEvaluationProvider.overrideWith(
            () => _FixedReviewController(
              const RetellReviewEvaluationState(
                attemptKey: 'retell:a1:0',
                phase: RetellReviewEvaluationPhase.failed,
                errorCode: 'audio_too_large',
              ),
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('The prepared recording exceeds the 2 MB limit.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(retried, 1);
  });

  testWidgets('首帧到达前显示骨架而非报告', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showRetellReviewSheet(
                context,
                recordingPath: '/tmp/retell.m4a',
                playbackService: playback,
                onBeforePlayback: () async {},
                onRetry: () async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: [
          retellReviewEvaluationProvider.overrideWith(
            () => _FixedReviewController(
              const RetellReviewEvaluationState(
                attemptKey: 'retell:a1:0',
                phase: RetellReviewEvaluationPhase.loading,
              ),
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();

    expect(find.text('AI Retell Review'), findsOneWidget);
    expect(find.byType(RetellReviewReport), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
