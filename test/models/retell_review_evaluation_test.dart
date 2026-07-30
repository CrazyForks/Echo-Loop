import 'package:echo_loop/models/retell_review_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('流式半成品结果防御性解析并保留已到达字段', () {
    final result = RetellReviewEvaluation.fromJson(<String, dynamic>{
      'summary': '表达了核心意思。',
      'rating': 'good',
      'strengths': [
        {'point': '信息完整'},
        null,
      ],
      'grammarErrors': 'not-a-list',
    });

    expect(result.summary, '表达了核心意思。');
    expect(result.rating, RetellReviewRating.good);
    expect(result.strengths.single.point, '信息完整');
    expect(result.strengths.single.evidence, '');
    expect(result.grammarErrors, isEmpty);
  });

  test('未知等级安全回退 keepGoing', () {
    final result = RetellReviewEvaluation.fromJson(<String, dynamic>{
      'rating': 'unexpected',
    });

    expect(result.rating, RetellReviewRating.keepGoing);
  });
}
