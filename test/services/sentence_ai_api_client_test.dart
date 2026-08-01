import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_io/io.dart';

import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_loop/models/dictionary/dictionary_entry.dart';
import 'package:echo_loop/models/retell_review_evaluation.dart';
import 'package:echo_loop/services/ai_http_client_adapter.dart';
import 'package:echo_loop/services/dictionary/dictionary_source.dart';
import 'package:echo_loop/services/sentence_ai_api_client.dart';

class MockDio extends Mock implements Dio {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDio mockDio;
  late SentenceAiApiClient client;
  late List<String> streamLogs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockDio = MockDio();
    streamLogs = <String>[];
    client = SentenceAiApiClient.withDio(
      mockDio,
      streamLogPrint: streamLogs.add,
    );
  });

  group('translateStream', () {
    Response<ResponseBody> ndjsonResponse(String ndjson, {int status = 200}) {
      final bytes = Uint8List.fromList(utf8.encode(ndjson));
      return Response(
        data: ResponseBody(Stream<Uint8List>.fromIterable([bytes]), status),
        statusCode: status,
        requestOptions: RequestOptions(
          path: '/api/v1/stream/translate',
          method: 'POST',
        ),
      );
    }

    String opsLine(List<Map<String, dynamic>> ops) =>
        '${jsonEncode({'ops': ops})}\n';

    test(
      '打到 /api/v1/stream/translate，带 text + 前后句 + Bearer，逐帧渐显 + done',
      () async {
        when(
          () => mockDio.post<ResponseBody>(
            '/api/v1/stream/translate',
            data: {
              'text': 'This is a test.',
              'previousText': 'Hello world.',
              'nextText': 'Goodbye now.',
            },
            options: any(
              named: 'options',
              that: isA<Options>().having(
                (o) => o.headers?['Authorization'],
                'Authorization',
                'Bearer access-token',
              ),
            ),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => ndjsonResponse(
            '${opsLine([
              {
                'p': ['translation'],
                'v': '这是',
              },
            ])}'
            '${opsLine([
              {
                'p': ['translation'],
                'v': '这是一个测试。',
              },
            ])}'
            '${jsonEncode({'done': true})}\n',
          ),
        );

        final frames = await client
            .translateStream(
              'This is a test.',
              previousText: 'Hello world.',
              nextText: 'Goodbye now.',
              accessToken: 'access-token',
            )
            .toList();

        // 两个 ops 批帧（isFinal=false）+ done 帧（isFinal=true），译文替换式渐显
        expect(frames.length, 3);
        expect(frames.first.isFinal, isFalse);
        expect(frames.first.translation.translation, '这是');
        expect(frames.last.isFinal, isTrue);
        expect(frames.last.translation.translation, '这是一个测试。');
      },
    );

    test('无前后句时请求体不含 previousText/nextText', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/translate',
          data: {'text': 'Hi.'},
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse('${jsonEncode({'done': true})}\n'),
      );

      await client.translateStream('Hi.', accessToken: 'access-token').toList();

      verify(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/translate',
          data: {'text': 'Hi.'},
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    });

    test('非 200（如 402）抛出带状态码的 DioException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/translate',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse(jsonEncode({'code': 'quota_exceeded'}), status: 402),
      );

      await expectLater(
        client.translateStream('test', accessToken: 'access-token').toList(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            402,
          ),
        ),
      );
      final log = streamLogs.join('\n');
      expect(log, contains('/api/v1/stream/translate'));
      expect(log, contains('402'));
      expect(log, contains('quota_exceeded'));
      expect(log, isNot(contains('access-token')));
    });

    test('流内 __error 帧抛出 SentenceTranslationStreamException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/translate',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse('${jsonEncode({'__error': 'unavailable'})}\n'),
      );

      await expectLater(
        client.translateStream('test', accessToken: 'access-token').toList(),
        throwsA(isA<SentenceTranslationStreamException>()),
      );
    });

    test('打印每条原始流式响应帧，便于调试', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/translate',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          '${opsLine([
            {
              'p': ['translation'],
              'v': '你好',
            },
          ])}'
          '${jsonEncode({'done': true})}\n',
        ),
      );

      await client.translateStream('Hi.', accessToken: 'access-token').toList();

      expect(streamLogs.length, 2);
      expect(streamLogs.first, contains('流式响应帧'));
      expect(streamLogs.first, contains('"ops"'));
      expect(streamLogs.first, contains('你好'));
      expect(streamLogs.last, contains('"done":true'));
    });
  });

  group('analyzeStream', () {
    /// 构造一个 NDJSON 字节流响应
    Response<ResponseBody> ndjsonResponse(String ndjson, {int status = 200}) {
      final bytes = Uint8List.fromList(utf8.encode(ndjson));
      return Response(
        data: ResponseBody(Stream<Uint8List>.fromIterable([bytes]), status),
        statusCode: status,
        requestOptions: RequestOptions(),
      );
    }

    String opsLine(List<Map<String, dynamic>> ops) =>
        '${jsonEncode({'ops': ops})}\n';

    test('打到 /api/v1/stream/analyze，带 text + Bearer，逐帧渐显 + done', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/analyze',
          data: {'text': 'She has been studying.'},
          options: any(
            named: 'options',
            that: isA<Options>().having(
              (o) => o.headers?['Authorization'],
              'Authorization',
              'Bearer access-token',
            ),
          ),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          '${opsLine([
            {
              'p': ['grammar', 0, 'point'],
              'v': '现在完成进行时',
            },
          ])}'
          '${opsLine([
            {
              'p': ['grammar', 0, 'note'],
              'v': '表持续动作',
            },
          ])}'
          '${jsonEncode({'done': true})}\n',
        ),
      );

      final frames = await client
          .analyzeStream('She has been studying.', accessToken: 'access-token')
          .toList();

      // 两个 ops 批帧（isFinal=false）+ done 帧（isFinal=true）
      expect(frames.length, 3);
      expect(frames.first.isFinal, isFalse);
      expect(frames.first.analysis.grammar.single.point, '现在完成进行时');
      expect(frames.last.isFinal, isTrue);
      expect(frames.last.analysis.grammar.single.note, '表持续动作');
    });

    test('非 200（如 402）抛出带状态码的 DioException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/analyze',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse(jsonEncode({'code': 'quota_exceeded'}), status: 402),
      );

      expect(
        () =>
            client.analyzeStream('test', accessToken: 'access-token').toList(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            402,
          ),
        ),
      );
    });

    test('流内 __error 帧抛出 SentenceAnalysisStreamException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/analyze',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse('${jsonEncode({'__error': 'unavailable'})}\n'),
      );

      expect(
        () =>
            client.analyzeStream('test', accessToken: 'access-token').toList(),
        throwsA(isA<SentenceAnalysisStreamException>()),
      );
    });
  });

  group('senseGroupsStream', () {
    /// 构造一个 NDJSON 字节流响应
    Response<ResponseBody> ndjsonResponse(String ndjson, {int status = 200}) {
      final bytes = Uint8List.fromList(utf8.encode(ndjson));
      return Response(
        data: ResponseBody(Stream<Uint8List>.fromIterable([bytes]), status),
        statusCode: status,
        requestOptions: RequestOptions(),
      );
    }

    String opsLine(List<Map<String, dynamic>> ops) =>
        '${jsonEncode({'ops': ops})}\n';

    test(
      '打到 /api/v1/stream/sense-groups，带 text + Bearer，medium 逐个渐显 + done',
      () async {
        when(
          () => mockDio.post<ResponseBody>(
            '/api/v1/stream/sense-groups',
            data: {'text': 'Hello world'},
            options: any(
              named: 'options',
              that: isA<Options>().having(
                (o) => o.headers?['Authorization'],
                'Authorization',
                'Bearer access-token',
              ),
            ),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => ndjsonResponse(
            // medium[0] → medium[1] 逐个到达，随后 fine，最后 done
            '${opsLine([
              {
                'p': ['medium', 0],
                'v': 'Hello',
              },
            ])}'
            '${opsLine([
              {
                'p': ['medium', 1],
                'v': ' world',
              },
            ])}'
            '${opsLine([
              {
                'p': ['fine', 0],
                'v': 'Hello',
              },
              {
                'p': ['fine', 1],
                'v': ' world',
              },
            ])}'
            '${jsonEncode({'done': true})}\n',
          ),
        );

        final frames = await client
            .senseGroupsStream('Hello world', accessToken: 'access-token')
            .toList();

        // 三个 ops 批帧（isFinal=false）+ done 帧（isFinal=true）
        expect(frames.length, 4);
        expect(frames.first.isFinal, isFalse);
        expect(frames.first.result.medium, ['Hello']);
        expect(frames.last.isFinal, isTrue);
        expect(frames.last.result.medium, ['Hello', ' world']);
        expect(frames.last.result.fine, ['Hello', ' world']);
      },
    );

    test('非 200（如 402）抛出带状态码的 DioException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/sense-groups',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse(jsonEncode({'code': 'quota_exceeded'}), status: 402),
      );

      expect(
        () => client
            .senseGroupsStream('test', accessToken: 'access-token')
            .toList(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            402,
          ),
        ),
      );
    });

    test('流内 __error 帧抛出 SenseGroupsStreamException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/sense-groups',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse('${jsonEncode({'__error': 'unavailable'})}\n'),
      );

      expect(
        () => client
            .senseGroupsStream('test', accessToken: 'access-token')
            .toList(),
        throwsA(isA<SenseGroupsStreamException>()),
      );
    });
  });

  group('流式查词', () {
    /// 构造一个 NDJSON 字节流响应
    Response<ResponseBody> ndjsonResponse(String ndjson, {int status = 200}) {
      final bytes = Uint8List.fromList(utf8.encode(ndjson));
      return Response(
        data: ResponseBody(Stream<Uint8List>.fromIterable([bytes]), status),
        statusCode: status,
        requestOptions: RequestOptions(),
      );
    }

    /// 构造一个 ops 增量批行：{"ops":[{p,v},...]}
    String opsLine(List<Map<String, dynamic>> ops) =>
        '${jsonEncode({'ops': ops})}\n';

    test(
      'lookupWordStream 打到 /api/v1/stream/lookup-word，ops 批逐帧 yield',
      () async {
        when(
          () => mockDio.post<ResponseBody>(
            '/api/v1/stream/lookup-word',
            data: any(named: 'data'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => ndjsonResponse(
            '${opsLine([
              {
                'p': ['headword'],
                'v': 'run',
              },
            ])}'
            '${opsLine([
              {
                'p': ['etymology'],
                'v': 'x',
              },
            ])}',
          ),
        );

        final frames = await client
            .lookupWordStream('run', accessToken: 'tok')
            .toList();

        // 两个 ops 批各 yield 一帧
        expect(frames.length, 2);
        expect(frames.first.headword, 'run');
        expect(frames.last.headword, 'run');
      },
    );

    test('单个 ops 批含多个叶子 → 只 yield 一帧且全部生效', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-word',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          '${opsLine([
            {
              'p': ['headword'],
              'v': 'run',
            },
            {
              'p': ['etymology'],
              'v': 'x',
            },
          ])}'
          '${jsonEncode({'done': true})}\n',
        ),
      );

      final frames = await client
          .lookupWordStreamFrames('run', accessToken: 'tok')
          .toList();

      // 一个多叶子 ops 批 → 1 帧；+ done 帧 = 2
      expect(frames.length, 2);
      final entry = frames.last.entry as DictionaryEntry;
      expect(entry.headword, 'run');
      expect(entry.etymology, 'x');
    });

    test('lookupWordStreamFrames：done 帧标记 isFinal，累积后 entry 无协议字段', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-word',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          '${opsLine([
            {
              'p': ['headword'],
              'v': 'run',
            },
          ])}'
          '${opsLine([
            {
              'p': ['etymology'],
              'v': 'x',
            },
          ])}'
          '${jsonEncode({'done': true})}\n',
        ),
      );

      final frames = await client
          .lookupWordStreamFrames('run', accessToken: 'tok')
          .toList();

      // 两个 ops 批帧（isFinal=false）+ done 帧（isFinal=true）
      expect(frames.length, 3);
      expect(frames.first.isFinal, isFalse);
      expect(frames.last.isFinal, isTrue);
      final json = frames.last.entry.toJson();
      expect(json, isNot(contains('__final')));
      expect(json, isNot(contains('ops')));
      expect(json, isNot(contains('done')));
      expect(frames.last.entry.headword, 'run');
    });

    test('lookupPhraseStream 打到 /api/v1/stream/lookup-phrase', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-phrase',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          opsLine([
            {
              'p': ['originalExpression'],
              'v': 'break a leg',
            },
          ]),
        ),
      );

      final frames = await client
          .lookupPhraseStream('break a leg', accessToken: 'tok')
          .toList();

      expect(frames.length, 1);
      expect(frames.first.headword, 'break a leg');
    });

    test('嵌套叶子路径累积成正确的嵌套结构', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-word',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          '${opsLine([
            {
              'p': ['headword'],
              'v': 'run',
            },
            {
              'p': ['meanings', 0, 'definition'],
              'v': '奔跑',
            },
          ])}'
          '${opsLine([
            {
              'p': ['meanings', 0, 'examples', 0, 'sentence'],
              'v': 'I run.',
            },
            {
              'p': ['meanings', 0, 'examples', 0, 'translation'],
              'v': '我跑。',
            },
          ])}'
          '${jsonEncode({'done': true})}\n',
        ),
      );

      final frames = await client
          .lookupWordStreamFrames('run', accessToken: 'tok')
          .toList();

      final entry = frames.last.entry as DictionaryEntry;
      expect(entry.headword, 'run');
      expect(entry.meanings.single.definition, '奔跑');
      expect(entry.meanings.single.examples.single.sentence, 'I run.');
      expect(entry.meanings.single.examples.single.translation, '我跑。');
    });

    test('流内 __error 帧 → 抛 DictionaryStreamException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-word',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse('${jsonEncode({'__error': 'unavailable'})}\n'),
      );

      await expectLater(
        client.lookupWordStream('run', accessToken: 'tok').toList(),
        throwsA(isA<DictionaryStreamException>()),
      );
    });

    test('损坏 NDJSON → 抛 DictionaryStreamException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-word',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => ndjsonResponse('{"headword":\n'));

      await expectLater(
        client.lookupWordStream('run', accessToken: 'tok').toList(),
        throwsA(isA<DictionaryStreamException>()),
      );
    });

    test(
      '400 + code=phrase_too_long → DictionaryPhraseTooLongException',
      () async {
        when(
          () => mockDio.post<ResponseBody>(
            '/api/v1/stream/lookup-phrase',
            data: any(named: 'data'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => ndjsonResponse(
            jsonEncode({'error': 'too long', 'code': 'phrase_too_long'}),
            status: 400,
          ),
        );

        await expectLater(
          client.lookupPhraseStream('a b c', accessToken: 'tok').toList(),
          throwsA(isA<DictionaryPhraseTooLongException>()),
        );
      },
    );

    test('401 → DictionaryAuthRequiredException', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-word',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async =>
            ndjsonResponse(jsonEncode({'error': 'unauthorized'}), status: 401),
      );

      await expectLater(
        client.lookupWordStream('run', accessToken: 'tok').toList(),
        throwsA(isA<DictionaryAuthRequiredException>()),
      );
    });

    test('402 → 带状态码的 DioException（供 controller 转额度态）', () async {
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/lookup-word',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          jsonEncode({'error': 'quota', 'code': 'quota_exceeded'}),
          status: 402,
        ),
      );

      await expectLater(
        client.lookupWordStream('run', accessToken: 'tok').toList(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            402,
          ),
        ),
      );
    });
  });

  group('evaluateReviewStream', () {
    Response<ResponseBody> bodyResponse(String body, {int status = 200}) {
      final bytes = Uint8List.fromList(utf8.encode(body));
      return Response(
        data: ResponseBody(Stream<Uint8List>.fromIterable([bytes]), status),
        statusCode: status,
        requestOptions: RequestOptions(
          path: '/api/v1/stream/evaluate-review',
          method: 'POST',
        ),
      );
    }

    Response<ResponseBody> ndjsonResponse(String ndjson) =>
        bodyResponse(ndjson);

    test('meta 首帧即产出一帧（先出转录），后续 ops 逐帧累积', () async {
      final file = File(
        '${Directory.systemTemp.path}/retell-review-client-test.m4a',
      );
      await file.writeAsBytes([0, 1, 2]);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/evaluate-review',
          data: any(named: 'data'),
          // 端点已鉴权化：不带 Bearer 的请求打不中这个 stub。
          options: any(
            named: 'options',
            that: isA<Options>().having(
              (o) => o.headers?['Authorization'],
              'Authorization',
              'Bearer access-token',
            ),
          ),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => ndjsonResponse(
          '${jsonEncode({
            'meta': {'transcript': 'I practiced today.'},
          })}\n'
          '${jsonEncode({
            'ops': [
              {
                'p': ['summary'],
                'v': '表达清楚。',
              },
              {
                'p': ['keyPoints', 0, 'keyPoint'],
                'v': '练习提升流利度',
              },
            ],
          })}\n'
          '${jsonEncode({
            'ops': [
              {
                'p': ['keyPoints', 0, 'status'],
                'v': 'covered',
              },
              {
                'p': ['keyPoints', 1, 'keyPoint'],
                'v': '睡眠巩固记忆',
              },
              {
                'p': ['keyPoints', 1, 'status'],
                'v': 'missed',
              },
              {
                'p': ['keyPoints', 1, 'feedback'],
                'v': '完全没有提到。',
              },
              {
                'p': ['suggestion'],
                'v': '复述前先列三个关键词。',
              },
              {
                'p': ['corrections', 0, 'type'],
                'v': 'grammar',
              },
              {
                'p': ['corrections', 0, 'transcript'],
                'v': "he don't know",
              },
              {
                'p': ['corrections', 0, 'correction'],
                'v': "he doesn't know",
              },
              {
                'p': ['rating'],
                'v': 'good',
              },
            ],
          })}\n'
          '${jsonEncode({'done': true})}\n',
        ),
      );

      final frames = await client
          .evaluateReviewStream(
            audioFile: file,
            originalText: 'Practice every day.',
            targetLanguage: 'zh-CN',
            accessToken: 'access-token',
          )
          .toList();

      expect(frames, hasLength(4));
      // meta 首帧独立成帧：AI 还没吐字，先让 UI 有转录可显示。
      final metaFrame = frames.first.evaluation;
      expect(metaFrame.transcript, 'I practiced today.');
      expect(metaFrame.summary, '');
      expect(metaFrame.keyPoints, isEmpty);
      expect(frames.first.isFinal, isFalse);

      // 第二帧：AI 首批文本到达，要点状态尚未到达。
      final second = frames[1].evaluation;
      expect(second.transcript, 'I practiced today.');
      expect(second.summary, '表达清楚。');
      expect(second.rating, isNull);
      expect(second.keyPoints.single.keyPoint, '练习提升流利度');
      expect(second.keyPoints.single.status, isNull);

      final last = frames.last.evaluation;
      expect(frames.last.isFinal, isTrue);
      expect(last.transcript, 'I practiced today.');
      expect(last.rating, RetellReviewRating.good);
      expect(last.suggestion, '复述前先列三个关键词。');
      expect(last.keyPoints, hasLength(2));
      expect(last.keyPoints.first.status, RetellReviewKeyPointStatus.covered);
      expect(last.keyPoints.last.status, RetellReviewKeyPointStatus.missed);
      expect(last.keyPoints.last.feedback, '完全没有提到。');
      expect(last.corrections.single.type, RetellReviewCorrectionType.grammar);
      expect(last.corrections.single.transcript, "he don't know");
      expect(last.corrections.single.correction, "he doesn't know");
      expect(last.corrections.single.explanation, '');
    });

    test('402 → 带状态码的 DioException（供 controller 转额度态）', () async {
      final file = File(
        '${Directory.systemTemp.path}/retell-review-quota-test.m4a',
      );
      await file.writeAsBytes([0, 1, 2]);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      when(
        () => mockDio.post<ResponseBody>(
          '/api/v1/stream/evaluate-review',
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => bodyResponse(
          jsonEncode({'error': 'quota', 'code': 'quota_exceeded'}),
          status: 402,
        ),
      );

      await expectLater(
        client
            .evaluateReviewStream(
              audioFile: file,
              originalText: 'Practice every day.',
              targetLanguage: 'zh-CN',
              accessToken: 'access-token',
            )
            .toList(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            402,
          ),
        ),
      );
    });
  });

  group('构造与销毁', () {
    test('普通构造函数创建实例', () {
      final c = SentenceAiApiClient(baseUrl: 'https://test.com');
      expect(c, isNotNull);
      expect(c.debugHttpClientAdapter, isA<Http2Adapter>());
      c.dispose();
    });

    test('withDio 构造函数接受自定义 Dio', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://mock.com'));
      final c = SentenceAiApiClient.withDio(dio);
      expect(c, isNotNull);
    });

    test('dispose 调用 Dio.close', () {
      when(
        () => mockDio.close(force: any(named: 'force')),
      ).thenAnswer((_) async {});
      client.dispose();
      verify(() => mockDio.close(force: false)).called(1);
    });
  });

  group('AI HTTP adapter', () {
    test('HTTPS API 默认启用 HTTP/2 adapter', () {
      final dio = Dio();

      configureAiHttpClientAdapter(dio, baseUrl: 'https://api.test');

      expect(shouldUseAiHttp2Adapter('https://api.test'), isTrue);
      expect(dio.httpClientAdapter, isA<Http2Adapter>());
    });

    test('HTTP 本地开发地址保持 Dio 默认 adapter', () {
      final dio = Dio();

      configureAiHttpClientAdapter(dio, baseUrl: 'http://localhost:3000');

      expect(shouldUseAiHttp2Adapter('http://localhost:3000'), isFalse);
      expect(dio.httpClientAdapter, isNot(isA<Http2Adapter>()));
    });

    test('显式关闭开关时保持 Dio 默认 adapter', () {
      final dio = Dio();

      configureAiHttpClientAdapter(
        dio,
        baseUrl: 'https://api.test',
        http2Enabled: false,
      );

      expect(
        shouldUseAiHttp2Adapter('https://api.test', http2Enabled: false),
        isFalse,
      );
      expect(dio.httpClientAdapter, isNot(isA<Http2Adapter>()));
    });
  });
}
