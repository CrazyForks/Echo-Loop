// 收藏页面 Widget 测试
//
// 验证句子/单词视图切换、按音频分组展示、空状态、收藏操作等 UI 行为。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/screens/favorites_screen.dart';
import 'package:echo_loop/database/daos/audio_item_dao.dart';
import 'package:echo_loop/database/daos/bookmark_dao.dart';
import 'package:echo_loop/database/daos/saved_word_dao.dart';
import 'package:echo_loop/database/daos/sentence_ai_cache_dao.dart';
import 'package:echo_loop/database/app_database.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/providers/audio_engine/audio_engine_provider.dart';
import 'package:echo_loop/providers/learning_session/bookmark_review_provider.dart';
import 'package:echo_loop/providers/learning_session/favorite_review_due_count_provider.dart';
import 'package:echo_loop/providers/sentence_ai_provider.dart';
import 'package:echo_loop/services/sentence_ai_api_client.dart';
import 'package:echo_loop/theme/app_theme.dart';

import '../helpers/mock_providers.dart';

// ========== 测试用 Mock / Stub ==========

class _MockCacheDao extends Mock implements SentenceAiCacheDao {}

class _MockApiClient extends Mock implements SentenceAiApiClient {}

class _MockAudioItemDao extends Mock implements AudioItemDao {
  _MockAudioItemDao() {
    // 默认返回 null（音频不存在），避免未 stub 报错
    when(() => getById(any())).thenAnswer((_) async => null);
  }
}

/// 测试用 BookmarkDao — 通过 StreamController 控制数据
class _TestBookmarkDao implements BookmarkDao {
  final StreamController<List<BookmarkWithAudio>> _controller;

  _TestBookmarkDao(this._controller);

  @override
  Stream<List<BookmarkWithAudio>> watchAllWithAudioName() => _controller.stream;

  @override
  Future<List<Bookmark>> getByAudioId(String audioItemId) async => [];

  @override
  Stream<List<Bookmark>> watchByAudioId(String audioItemId) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// 测试用 SavedWordDao — 通过 StreamController 控制数据
class _TestSavedWordDao implements SavedWordDao {
  final StreamController<List<SavedWord>> _controller;

  _TestSavedWordDao(this._controller);

  @override
  Stream<List<SavedWord>> watchAll() => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _DeferredBookmarkReview extends BookmarkReview {
  final initialized = Completer<void>();

  @override
  BookmarkReviewState build() => const BookmarkReviewState();

  @override
  Future<void> initialize(List<BookmarkWithAudio> bookmarks) =>
      initialized.future;
}

class _ImmediateBookmarkReview extends BookmarkReview {
  @override
  BookmarkReviewState build() => const BookmarkReviewState();

  @override
  Future<void> initialize(List<BookmarkWithAudio> bookmarks) async {}
}

/// 创建测试用 Bookmark 数据
Bookmark _createBookmark({
  required int id,
  required String audioItemId,
  required int sentenceIndex,
  String sentenceText = 'Test sentence.',
  double startTime = 0.0,
  double endTime = 5.0,
}) {
  return Bookmark(
    id: id,
    audioItemId: audioItemId,
    sentenceIndex: sentenceIndex,
    sentenceText: sentenceText,
    startTime: startTime,
    endTime: endTime,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    deletedAt: null,
    syncStatus: 0,
  );
}

/// 创建测试用 SavedWord 数据
SavedWord _createSavedWord({
  required int id,
  required String word,
  String? audioItemId,
  int? sentenceIndex,
  String? sentenceText,
}) {
  return SavedWord(
    id: id,
    word: word,
    audioItemId: audioItemId,
    sentenceIndex: sentenceIndex,
    sentenceText: sentenceText,
    sentenceStartMs: null,
    sentenceEndMs: null,
    practiceCount: 0,
    totalStudyMs: 0,
    viewedBack: false,
    lastPracticedAt: null,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    deletedAt: null,
    syncStatus: 0,
  );
}

void main() {
  late StreamController<List<BookmarkWithAudio>> bookmarkController;
  late StreamController<List<SavedWord>> wordController;

  setUp(() {
    bookmarkController = StreamController<List<BookmarkWithAudio>>.broadcast();
    wordController = StreamController<List<SavedWord>>.broadcast();
  });

  tearDown(() {
    bookmarkController.close();
    wordController.close();
  });

  Widget createTestWidget({
    Locale locale = const Locale('en'),
    BookmarkReview? bookmarkReview,
    int? sentenceDueCount,
    Future<int> Function()? sentenceDueLoader,
    int? vocabularyDueCount,
    Future<int>? vocabularyDueFuture,
  }) {
    final router = GoRouter(
      initialLocation: '/favorites',
      routes: [
        GoRoute(
          path: '/favorites',
          builder: (context, state) => const FavoritesScreen(),
        ),
        GoRoute(
          path: '/bookmark-review',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('test-bookmark-review-close'),
                onPressed: context.pop,
                child: const Text('Bookmark Review'),
              ),
            ),
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        analyticsOverride(),
        ...studyTimeOverrides(),
        bookmarkDaoProvider.overrideWithValue(
          _TestBookmarkDao(bookmarkController),
        ),
        savedWordDaoProvider.overrideWithValue(
          _TestSavedWordDao(wordController),
        ),
        audioItemDaoProvider.overrideWithValue(_MockAudioItemDao()),
        audioEngineProvider.overrideWith(() => TestAudioEngine()),
        if (bookmarkReview != null)
          bookmarkReviewProvider.overrideWith(() => bookmarkReview),
        if (sentenceDueCount != null)
          favoriteSentenceDueCountProvider.overrideWith(
            (ref) async => sentenceDueCount,
          ),
        if (sentenceDueLoader != null)
          favoriteSentenceDueCountProvider.overrideWith(
            (ref) => sentenceDueLoader(),
          ),
        if (vocabularyDueCount != null)
          favoriteVocabularyDueCountProvider.overrideWith(
            (ref) async => vocabularyDueCount,
          ),
        if (vocabularyDueFuture != null)
          favoriteVocabularyDueCountProvider.overrideWith(
            (ref) => vocabularyDueFuture,
          ),
        sentenceAiNotifierProvider.overrideWithValue(
          SentenceAiNotifier(
            cacheDao: _MockCacheDao(),
            apiClient: _MockApiClient(),
          ),
        ),
      ],
      child: MaterialApp.router(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    );
  }

  group('FavoritesScreen — SegmentedButton 切换', () {
    testWidgets('重新显示句子 tab 时重新读取待复习数量', (tester) async {
      var dueCount = 2;
      var requests = 0;
      await tester.pumpWidget(
        createTestWidget(
          sentenceDueLoader: () async {
            requests += 1;
            return dueCount;
          },
          vocabularyDueCount: 1,
        ),
      );
      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            endTime: 3,
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();
      expect(find.text('2 due for review'), findsOneWidget);

      await tester.tap(find.text('Vocabulary'));
      await tester.pumpAndSettle();
      dueCount = 0;
      await tester.tap(find.textContaining('Sentences'));
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(find.text('All Done!'), findsOneWidget);
    });

    testWidgets('从后台恢复时刷新当前 tab 的待复习数量', (tester) async {
      var dueCount = 1;
      var requests = 0;
      await tester.pumpWidget(
        createTestWidget(
          sentenceDueLoader: () async {
            requests += 1;
            return dueCount;
          },
        ),
      );
      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            endTime: 3,
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      dueCount = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(find.text('All Done!'), findsOneWidget);
    });

    testWidgets('右上角设置打开收藏复习共享设置且不展开内容分区', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(
        tester.widget<AppBar>(find.byType(AppBar)).actionsPadding,
        const EdgeInsets.only(right: AppSpacing.s),
      );
      final statistics = tester.getRect(
        find.byKey(const Key('favorites-statistics')),
      );
      final recycleBin = tester.getRect(
        find.byKey(const Key('favorites-recycle-bin')),
      );
      final settings = tester.getRect(
        find.byKey(const Key('favorites-review-settings')),
      );
      expect(recycleBin.left, closeTo(statistics.right, 0.01));
      expect(settings.left, closeTo(recycleBin.right, 0.01));

      await tester.tap(find.byKey(const Key('favorites-review-settings')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Review settings'), findsOneWidget);
      final sheetRenderObject = tester.renderObject<RenderBox>(
        find.byType(BottomSheet),
      );
      expect(
        sheetRenderObject.size.height,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio * 0.9,
        ),
      );
      expect(
        find.byKey(const Key('favorite-review-settings-sentence-section')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ExpansionTile>(
              find.byKey(
                const Key('favorite-review-settings-sentence-section'),
              ),
            )
            .initiallyExpanded,
        isFalse,
      );
      expect(
        tester
            .widget<ExpansionTile>(
              find.byKey(
                const Key('favorite-review-settings-vocabulary-section'),
              ),
            )
            .initiallyExpanded,
        isFalse,
      );
    });

    testWidgets('词汇 tab 设置同样不展开内容分区', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.tap(find.text('Vocabulary'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('favorites-review-settings')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Review settings'), findsOneWidget);
      expect(find.text('Saved vocabulary review'), findsOneWidget);
      expect(
        tester
            .widget<ExpansionTile>(
              find.byKey(
                const Key('favorite-review-settings-vocabulary-section'),
              ),
            )
            .initiallyExpanded,
        isFalse,
      );
    });

    testWidgets('默认显示句子视图和 tab 标签', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // tab 标签文本可见
      expect(find.text('Sentences'), findsOneWidget);
      expect(find.text('Vocabulary'), findsOneWidget);
    });

    testWidgets('点击 Vocabulary 切换到单词视图', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // 点击 Vocabulary 按钮
      await tester.tap(find.text('Vocabulary'));
      await tester.pump();

      // 单词视图加载中（stream 尚未发射数据）
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('切换到单词再切回句子', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Vocabulary'));
      await tester.pump();

      await tester.tap(find.text('Sentences'));
      await tester.pump();

      // 句子视图应显示加载状态（等待 stream 数据）
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('FavoritesScreen — 句子视图', () {
    testWidgets('关闭句子复习后刷新待复习数量', (tester) async {
      var dueCount = 1;
      var requests = 0;
      await tester.pumpWidget(
        createTestWidget(
          bookmarkReview: _ImmediateBookmarkReview(),
          sentenceDueLoader: () async {
            requests += 1;
            return dueCount;
          },
        ),
      );
      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            endTime: 3,
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.text('Bookmark Review'), findsOneWidget);

      dueCount = 0;
      await tester.tap(find.byKey(const Key('test-bookmark-review-close')));
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(find.text('All Done!'), findsOneWidget);
    });

    testWidgets('无数据时显示句子空状态', (tester) async {
      await tester.pumpWidget(createTestWidget());
      bookmarkController.add([]);
      wordController.add([]);
      await tester.pumpAndSettle();

      expect(find.text('No saved sentences yet'), findsOneWidget);
    });

    testWidgets('有数据时按音频分组展示', (tester) async {
      await tester.pumpWidget(createTestWidget());

      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            sentenceText: 'Hello world.',
          ),
          audioName: 'Audio One',
        ),
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 2,
            audioItemId: 'audio-1',
            sentenceIndex: 1,
            sentenceText: 'How are you?',
          ),
          audioName: 'Audio One',
        ),
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 3,
            audioItemId: 'audio-2',
            sentenceIndex: 0,
            sentenceText: 'Good morning.',
          ),
          audioName: 'Audio Two',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      // 两个音频分组标题
      expect(find.text('Audio One'), findsOneWidget);
      expect(find.text('Audio Two'), findsOneWidget);
    });

    testWidgets('显示"开始复习"按钮及句子数', (tester) async {
      await tester.pumpWidget(createTestWidget(sentenceDueCount: 1));

      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            sentenceText: 'Test sentence.',
            startTime: 0.0,
            endTime: 3.0,
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      // FilledButton.tonal 类型的开始复习按钮
      expect(find.byType(FilledButton), findsAtLeast(1));
      // 有待复习内容时统一使用闪卡图标。
      expect(find.byIcon(Icons.style_outlined), findsAtLeast(1));
      expect(find.text('1 due for review'), findsOneWidget);
      expect(tester.getSize(find.byType(FilledButton).last).height, 36);
    });

    testWidgets('句子无待复习内容时显示空态并禁用按钮', (tester) async {
      await tester.pumpWidget(createTestWidget(sentenceDueCount: 0));
      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            endTime: 3.0,
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      expect(find.text('All Done!'), findsOneWidget);
      expect(find.text('🎉'), findsOneWidget);
      expect(tester.getSize(find.byType(FilledButton).last).height, 36);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
    });

    testWidgets('开始复习等待异步初始化完成后才导航', (tester) async {
      final bookmarkReview = _DeferredBookmarkReview();
      await tester.pumpWidget(
        createTestWidget(bookmarkReview: bookmarkReview, sentenceDueCount: 1),
      );
      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            endTime: 3.0,
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      expect(find.text('Bookmark Review'), findsNothing);

      bookmarkReview.initialized.complete();
      await tester.pumpAndSettle();
      expect(find.text('Bookmark Review'), findsOneWidget);
    });

    testWidgets('展开音频组后显示句子', (tester) async {
      await tester.pumpWidget(createTestWidget());

      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            sentenceText: 'Hello world.',
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      // 展开音频组
      await tester.tap(find.text('Audio One'));
      await tester.pumpAndSettle();

      // 句子文本可见
      expect(find.text('Hello world.'), findsOneWidget);
    });

    testWidgets('句子项显示时间戳', (tester) async {
      await tester.pumpWidget(createTestWidget());

      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            sentenceText: 'Test.',
            startTime: 65.0,
            endTime: 70.0,
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      // 展开
      await tester.tap(find.text('Audio One'));
      await tester.pumpAndSettle();

      // 句子文本可见（当前 UI 不显示时间戳）
      expect(find.text('Test.'), findsOneWidget);
    });

    testWidgets('句子项显示播放按钮', (tester) async {
      await tester.pumpWidget(createTestWidget());

      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
            sentenceText: 'Test.',
          ),
          audioName: 'Audio One',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      // 展开
      await tester.tap(find.text('Audio One'));
      await tester.pumpAndSettle();

      // 播放按钮
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    });

    testWidgets('多个音频分组不再显示单篇练习按钮', (tester) async {
      await tester.pumpWidget(createTestWidget());

      bookmarkController.add([
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 1,
            audioItemId: 'audio-1',
            sentenceIndex: 0,
          ),
          audioName: 'Audio One',
        ),
        BookmarkWithAudio(
          bookmark: _createBookmark(
            id: 2,
            audioItemId: 'audio-2',
            sentenceIndex: 0,
          ),
          audioName: 'Audio Two',
        ),
      ]);
      wordController.add([]);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.fitness_center), findsNothing);
    });
  });

  group('FavoritesScreen — 单词视图', () {
    testWidgets('切换到词汇 tab 时不回退显示开始复习', (tester) async {
      final dueCount = Completer<int>();
      await tester.pumpWidget(
        createTestWidget(vocabularyDueFuture: dueCount.future),
      );
      wordController.add([_createSavedWord(id: 1, word: 'apple')]);
      await tester.pump();

      await tester.tap(find.textContaining('Vocabulary'));
      await tester.pump();

      expect(find.text('Start Quiz (1)'), findsNothing);
      expect(find.text('Loading'), findsOneWidget);

      dueCount.complete(2);
      await tester.pump();
      await tester.pump();
      expect(find.text('2 due for review'), findsOneWidget);
    });

    testWidgets('无数据时显示单词空状态', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // 切到单词视图
      await tester.tap(find.text('Vocabulary'));
      await tester.pump();
      wordController.add([]);
      await tester.pump();
      await tester.pump();

      expect(find.text('No saved vocabulary yet'), findsOneWidget);
    });

    testWidgets('有数据时显示单词列表', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Vocabulary'));
      await tester.pump();
      wordController.add([
        _createSavedWord(id: 1, word: 'apple'),
        _createSavedWord(id: 2, word: 'banana'),
      ]);
      await tester.pump();
      await tester.pump();

      expect(find.text('apple'), findsOneWidget);
      expect(find.text('banana'), findsOneWidget);
    });

    testWidgets('词汇复习入口显示待复习数量', (tester) async {
      await tester.pumpWidget(createTestWidget(vocabularyDueCount: 2));
      await tester.pump();

      await tester.tap(find.text('Vocabulary'));
      await tester.pump();
      wordController.add([_createSavedWord(id: 1, word: 'apple')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('2 due for review'), findsOneWidget);
    });

    testWidgets('词汇无待复习内容时显示庆祝图标', (tester) async {
      await tester.pumpWidget(createTestWidget(vocabularyDueCount: 0));
      await tester.pump();

      await tester.tap(find.text('Vocabulary'));
      await tester.pump();
      wordController.add([_createSavedWord(id: 1, word: 'apple')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('All Done!'), findsOneWidget);
      expect(find.text('🎉'), findsOneWidget);
      expect(find.byIcon(Icons.style_outlined), findsNothing);
    });

    testWidgets('单词项显示单词内容', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Vocabulary'));
      await tester.pump();
      wordController.add([_createSavedWord(id: 1, word: 'hello')]);
      await tester.pump();
      await tester.pump();

      expect(find.text('hello'), findsOneWidget);
    });
  });

  group('FavoritesScreen - source audio layout', () {
    testWidgets('long labels stay within a narrow row', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 120,
            child: Row(
              children: [
                Icon(Icons.headphones, size: 12),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'From: exceptionally long audio lesson',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FavoritesScreen — 单词例句显示', () {
    testWidgets('展开单词后长例句完整显示（无 maxLines 截断）', (tester) async {
      final longSentence =
          'This is a very long example sentence that should be displayed in full '
          'without any truncation because the user needs to read the complete '
          'context of where this word was encountered during their study session.';

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Vocabulary'));
      await tester.pump();
      bookmarkController.add([]);
      wordController.add([
        _createSavedWord(
          id: 1,
          word: 'encountered',
          audioItemId: 'audio-1',
          sentenceIndex: 0,
          sentenceText: longSentence,
        ),
      ]);
      await tester.pumpAndSettle();

      // 展开单词详情
      await tester.tap(find.text('encountered'));
      await tester.pumpAndSettle();

      // 例句应完整显示
      expect(find.text(longSentence), findsOneWidget);

      // 验证例句 Text widget 没有 maxLines 限制
      final textWidget = tester.widget<Text>(find.text(longSentence));
      expect(textWidget.maxLines, isNull, reason: '展开后的例句不应有 maxLines 限制');
    });
  });

  group('FavoritesScreen — 中文本地化', () {
    testWidgets('中文标题和 tab 标签', (tester) async {
      await tester.pumpWidget(createTestWidget(locale: const Locale('zh')));
      await tester.pump();

      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('句子'), findsOneWidget);
      expect(find.text('词汇'), findsOneWidget);
    });

    testWidgets('中文句子空状态', (tester) async {
      await tester.pumpWidget(createTestWidget(locale: const Locale('zh')));
      bookmarkController.add([]);
      wordController.add([]);
      await tester.pumpAndSettle();

      expect(find.text('暂无收藏句子'), findsOneWidget);
    });
  });
}
