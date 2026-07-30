import 'package:echo_loop/models/retell_review_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('完整 schema 解析出全部字段', () {
    final result = RetellReviewEvaluation.fromJson(<String, dynamic>{
      'summary': '你准确传达了主要观点。',
      'keyPoints': [
        {'keyPoint': '练习提升流利度', 'status': 'covered', 'feedback': null},
        {'keyPoint': '反馈很重要', 'status': 'partial', 'feedback': '只说了一半。'},
        {'keyPoint': '睡眠巩固记忆', 'status': 'missed', 'feedback': '完全没有提到。'},
        {'keyPoint': '因果关系', 'status': 'distorted', 'feedback': '把因果说反了。'},
      ],
      'suggestion': '复述前先列三个关键词。',
      'grammarErrors': [
        {
          'transcript': 'he don\'t know',
          'correction': 'he doesn\'t know',
          'explanation': '第三人称单数用 doesn\'t。',
        },
      ],
      'rating': 'excellent',
    });

    expect(result.summary, '你准确传达了主要观点。');
    expect(result.rating, RetellReviewRating.excellent);
    expect(result.suggestion, '复述前先列三个关键词。');
    expect(
      result.keyPoints.map((e) => e.status).toList(),
      RetellReviewKeyPointStatus.values,
    );
    // 服务端 covered 时 feedback 为 null，模型统一收敛成空串。
    expect(result.keyPoints.first.feedback, '');
    expect(result.keyPoints[1].feedback, '只说了一半。');
    expect(result.grammarErrors.single.transcript, 'he don\'t know');
    expect(result.grammarErrors.single.correction, 'he doesn\'t know');
    expect(result.grammarErrors.single.explanation, '第三人称单数用 doesn\'t。');
  });

  test('最低评级 token poor 正确映射', () {
    final result = RetellReviewEvaluation.fromJson(<String, dynamic>{
      'rating': 'poor',
    });

    expect(result.rating, RetellReviewRating.poor);
  });

  test('评级缺失或无法识别时为 null，不兜底成最差评级', () {
    expect(RetellReviewEvaluation.fromJson(const {}).rating, isNull);
    expect(
      RetellReviewEvaluation.fromJson(<String, dynamic>{
        'rating': 'unexpected',
      }).rating,
      isNull,
    );
  });

  test('流式半成品：要点文本先到、状态未到时 status 为 null', () {
    final result = RetellReviewEvaluation.fromJson(<String, dynamic>{
      'summary': '表达了核心意思。',
      'keyPoints': [
        {'keyPoint': '练习提升流利度'},
        null,
      ],
      'grammarErrors': 'not-a-list',
    });

    expect(result.summary, '表达了核心意思。');
    expect(result.rating, isNull);
    expect(result.keyPoints, hasLength(1));
    expect(result.keyPoints.single.keyPoint, '练习提升流利度');
    expect(result.keyPoints.single.status, isNull);
    expect(result.keyPoints.single.feedback, '');
    expect(result.suggestion, '');
    expect(result.grammarErrors, isEmpty);
  });

  test('转录先到、AI 字段全空时也是合法快照', () {
    final result = RetellReviewEvaluation.fromJson(<String, dynamic>{
      'transcript': 'I practiced today.',
    });

    expect(result.transcript, 'I practiced today.');
    expect(result.summary, '');
    expect(result.rating, isNull);
    expect(result.keyPoints, isEmpty);
    expect(result.suggestion, '');
    expect(result.grammarErrors, isEmpty);
  });
}
