/// SelectableSentenceText（可点词 + 系统自由选区）交互测试
///
/// 组件与 DictionaryPanelHost 组合验证：点词查词、点空白不触发、
/// 自定义操作条、字符级拖选、面板与选区同步关闭、onBeforeLookup 时机。
library;

import 'dart:async';

import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:echo_loop/features/remote_config/remote_config.dart';
import 'package:echo_loop/features/remote_config/remote_config_providers.dart';
import 'package:echo_loop/features/onboarding_survey/providers/onboarding_survey_provider.dart';
import 'package:echo_loop/database/daos/saved_word_dao.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/models/dict_entry.dart';
import 'package:echo_loop/models/dictionary/dictionary_lookup_result.dart';
import 'package:echo_loop/models/speech_practice_models.dart';
import 'package:echo_loop/providers/dictionary/dictionary_registry.dart';
import 'package:echo_loop/providers/dictionary/lookup_controller.dart';
import 'package:echo_loop/providers/dictionary/visible_sources_provider.dart';
import 'package:echo_loop/providers/saved_sense_group_provider.dart';
import 'package:echo_loop/providers/saved_word_provider.dart';
import 'package:echo_loop/services/dictionary/dictionary_source.dart';
import 'package:echo_loop/services/dictionary_service.dart';
import 'package:echo_loop/theme/app_theme.dart';
import 'package:echo_loop/widgets/dictionary/dictionary_panel_host.dart';
import 'package:echo_loop/widgets/practice/selectable_sentence_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_providers.dart';

class _MockDictionaryService extends Mock implements DictionaryService {}

/// 固定收藏单词集合的 fake（绕过 DB）
class _FakeSavedWordTexts extends SavedWordTexts {
  final Set<String> value;
  _FakeSavedWordTexts(this.value);
  @override
  Stream<Set<String>> build() => Stream.value(value);
}

/// 固定收藏意群集合的 fake（绕过 DB）
class _FakeSavedSenseGroupTexts extends SavedSenseGroupTexts {
  final Set<String> value;
  _FakeSavedSenseGroupTexts(this.value);
  @override
  Stream<Set<String>> build() => Stream.value(value);
}

/// 记录选区收藏参数的 SavedWordDao，并提供可流式更新的收藏 key。
class _RecordingSavedWordDao implements SavedWordDao {
  _RecordingSavedWordDao([Set<String> initialWords = const {}])
    : storedWords = {...initialWords};

  final Set<String> storedWords;
  final StreamController<Set<String>> _savedWordsController =
      StreamController<Set<String>>.broadcast();

  String? savedWord;
  String? removedWord;
  String? audioItemId;
  int? sentenceIndex;
  String? sentenceText;
  int? sentenceStartMs;
  int? sentenceEndMs;

  @override
  Stream<List<SavedWord>> watchAll() => Stream.value(const <SavedWord>[]);

  @override
  Stream<Set<String>> watchSavedWordTexts() async* {
    yield Set<String>.unmodifiable(storedWords);
    yield* _savedWordsController.stream;
  }

  @override
  Stream<bool> watchIsWordSaved(String word) =>
      watchSavedWordTexts().map((words) => words.contains(word)).distinct();

  @override
  Future<void> saveWord({
    required String word,
    String? audioItemId,
    int? sentenceIndex,
    String? sentenceText,
    int? sentenceStartMs,
    int? sentenceEndMs,
  }) async {
    savedWord = word;
    this.audioItemId = audioItemId;
    this.sentenceIndex = sentenceIndex;
    this.sentenceText = sentenceText;
    this.sentenceStartMs = sentenceStartMs;
    this.sentenceEndMs = sentenceEndMs;
    storedWords.add(word);
    _savedWordsController.add(Set<String>.unmodifiable(storedWords));
  }

  @override
  Future<void> removeWord(String word) async {
    removedWord = word;
    storedWords.remove(word);
    _savedWordsController.add(Set<String>.unmodifiable(storedWords));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 回显查询词的 fake 本地源（记录收到的查询）
class _EchoLocalSource implements DictionarySource {
  final List<String> queries = [];
  @override
  String get id => 'local';
  @override
  IconData get icon => Icons.abc;
  @override
  bool get canBeDisabled => false;
  @override
  bool get requiresNetwork => false;

  @override
  Future<DictionaryLookupResult?> lookup(
    DictionaryLookupRequest request, {
    CancelToken? cancelToken,
  }) async {
    queries.add(request.word);
    return LocalDictResult(
      DictEntry(word: request.word, phonetic: 'x', translation: '释义'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DictionaryService oldInstance;
  late SharedPreferences prefs;
  late _EchoLocalSource source;
  String? clipboardText;
  final hapticCalls = <Object?>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final mock = _MockDictionaryService();
    when(() => mock.isAvailable).thenReturn(true);
    oldInstance = DictionaryService.replaceInstance(mock);
    source = _EchoLocalSource();
    clipboardText = null;
    hapticCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments;
            if (arguments is Map) {
              final text = arguments['text'];
              if (text is String) clipboardText = text;
            }
          }
          if (call.method == 'HapticFeedback.vibrate') {
            hapticCalls.add(call.arguments);
          }
          return null;
        });
  });

  tearDown(() {
    DictionaryService.replaceInstance(oldInstance);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final hostKey = GlobalKey<DictionaryPanelHostState>();

  Widget wrap({
    String text = 'alpha beta gamma',
    List<SpeechTranscriptSegment>? segments,
    Locale locale = const Locale('en'),
    DictionaryLookupOrigin origin = const DictionaryLookupOrigin(
      sentenceText: 'ctx',
    ),
    VoidCallback? onBeforeLookup,
    Widget Function(Widget sentence)? layout,
    List<Override> overrides = const [],
  }) => ProviderScope(
    // 调用方 overrides 置于列表末尾：Riverpod 重复 override 为 last-wins，
    // 保证调用方能覆盖同名默认 provider（与 createTestApp 约定一致）
    overrides: [
      analyticsOverride(),
      dictionaryOverride(),
      sharedPreferencesProvider.overrideWithValue(prefs),
      dictionarySourcesProvider.overrideWithValue([source]),
      dictionarySourcesByIdProvider.overrideWithValue({'local': source}),
      resolvedDefaultSourceIdProvider.overrideWithValue('local'),
      dictionaryLookupContextProvider.overrideWithValue(
        const DictionaryLookupContext(
          accessToken: 'tok',
          targetLanguage: 'zh-CN',
        ),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: Scaffold(
        body: DictionaryPanelHost(
          key: hostKey,
          child: Builder(
            builder: (context) {
              final sentence = SelectableSentenceText(
                text: text,
                highlightedSegments: segments,
                origin: origin,
                onBeforeLookup: onBeforeLookup,
              );
              if (layout != null) return layout(sentence);
              return Align(alignment: Alignment.topLeft, child: sentence);
            },
          ),
        ),
      ),
    ),
  );

  /// 取句中某个词的系统文本几何中心。
  Offset wordCenter(WidgetTester tester, String word) {
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final text = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller
        .text;
    final start = text.indexOf(word);
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + word.length),
    );
    return editable.localToGlobal(boxes.first.toRect().center);
  }

  /// 点击句中某个词的中心。
  Future<void> tapWord(WidgetTester tester, String word) async {
    await tester.tapAt(wordCenter(tester, word));
  }

  /// 取句子 SelectableText.rich 的全部子 span。
  List<TextSpan> sentenceSpans(WidgetTester tester) {
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    return selectable.textSpan!.children!.cast<TextSpan>();
  }

  testWidgets('点词：打开面板查询该词（剥标点交给归一化），onBeforeLookup 先触发', (tester) async {
    var beforeCalls = 0;
    await tester.pumpWidget(wrap(onBeforeLookup: () => beforeCalls++));
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();

    expect(beforeCalls, 1);
    expect(find.byKey(const Key('dict_sheet_sizer')), findsOneWidget);
    expect(source.queries, ['beta']);
    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    expect(
      editableState.textEditingValue.selection.textInside(
        editableState.textEditingValue.text,
      ),
      'beta',
    );
    expect(editableState.selectionOverlay?.toolbarIsVisible, isTrue);
  });

  testWidgets(
    'Apple 平台使用系统蓝选区和系统手柄，并用 tight 高亮贴合文字中线',
    (tester) async {
      await tester.pumpWidget(wrap());
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.textSpan, isNotNull);
      final context = tester.element(find.byType(SelectableText));
      final expectedColor = CupertinoColors.systemBlue
          .resolveFrom(context)
          .withValues(alpha: 0.2);
      final expectedHandleColor = CupertinoColors.systemBlue.resolveFrom(
        context,
      );
      expect(DefaultSelectionStyle.of(context).selectionColor, expectedColor);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).selectionColor,
        expectedColor,
      );
      expect(
        CupertinoTheme.of(context).selectionHandleColor,
        expectedHandleColor,
      );
      expect(selectable.selectionHeightStyle, ui.BoxHeightStyle.tight);
      expect(selectable.selectionControls, isNull);
      expect(selectable.contextMenuBuilder, isNotNull);
      expect(find.byKey(const Key('word_handle_start')), findsNothing);
      expect(find.byKey(const Key('word_handle_end')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android 句子讲解文本使用平台选择蓝，不回落到 App 主题色',
    (tester) async {
      await tester.pumpWidget(wrap());
      final context = tester.element(find.byType(SelectableText));
      final expectedColor = Colors.blue.withValues(alpha: 0.4);
      expect(DefaultSelectionStyle.of(context).selectionColor, expectedColor);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).selectionColor,
        expectedColor,
      );
      expect(TextSelectionTheme.of(context).selectionHandleColor, Colors.blue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('自定义操作条显示复制、收藏和问 AI', (tester) async {
    await tester.pumpWidget(
      wrap(
        overrides: [
          remoteFeatureEnabledProvider(
            RemoteFeature.aiChatAssistant,
          ).overrideWithValue(true),
        ],
      ),
    );
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('selection_toolbar_button_Copy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('selection_toolbar_button_Save')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('selection_toolbar_button_Ask AI')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('selection_toolbar_surface')),
      findsOneWidget,
    );
    expect(find.text('Share'), findsNothing);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('AI 远程开关关闭时操作条仍显示复制和收藏', (tester) async {
    await tester.pumpWidget(
      wrap(
        overrides: [
          remoteFeatureEnabledProvider(
            RemoteFeature.aiChatAssistant,
          ).overrideWithValue(false),
        ],
      ),
    );
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('selection_toolbar_button_Copy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('selection_toolbar_button_Save')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('selection_toolbar_button_Ask AI')),
      findsNothing,
    );
  });

  testWidgets('收藏多词选区：按词汇规则归一化、保存来源并保留查词现场', (tester) async {
    final dao = _RecordingSavedWordDao();
    const origin = DictionaryLookupOrigin(
      audioItemId: 'audio-1',
      sentenceIndex: 7,
      sentenceText: 'Alpha   beta, gamma',
      sentenceStartMs: 1200,
      sentenceEndMs: 3400,
    );
    await tester.pumpWidget(
      wrap(
        text: 'Alpha   beta, gamma',
        origin: origin,
        overrides: [
          savedWordDaoProvider.overrideWithValue(dao),
          usageOverride(),
          notificationPermissionOverride(),
          remoteFeatureEnabledProvider(
            RemoteFeature.aiChatAssistant,
          ).overrideWithValue(false),
        ],
      ),
    );
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();

    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    final value = editableState.textEditingValue;
    editableState.userUpdateTextEditingValue(
      value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 13),
      ),
      SelectionChangedCause.toolbar,
    );
    editableState.showToolbar();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection_toolbar_button_Save')));
    await tester.pumpAndSettle();

    expect(dao.savedWord, 'alpha beta');
    expect(dao.audioItemId, 'audio-1');
    expect(dao.sentenceIndex, 7);
    expect(dao.sentenceText, 'Alpha   beta, gamma');
    expect(dao.sentenceStartMs, 1200);
    expect(dao.sentenceEndMs, 3400);
    expect(editableState.textEditingValue.selection.isCollapsed, isFalse);
    expect(find.byKey(const Key('dict_sheet_sizer')), findsOneWidget);
    expect(
      find.byKey(const Key('selection_toolbar_button_Save')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('selection_toolbar_button_Remove')),
      findsOneWidget,
    );
  });

  testWidgets('已收藏选区显示取消收藏，并复用词汇移除流程', (tester) async {
    final dao = _RecordingSavedWordDao({'beta'});
    await tester.pumpWidget(
      wrap(
        overrides: [
          savedWordDaoProvider.overrideWithValue(dao),
          usageOverride(),
          notificationPermissionOverride(),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('selection_toolbar_button_Remove')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('selection_toolbar_button_Remove')));
    await tester.pumpAndSettle();

    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    expect(dao.removedWord, 'beta');
    expect(editableState.textEditingValue.selection.isCollapsed, isFalse);
    expect(find.byKey(const Key('dict_sheet_sizer')), findsOneWidget);
    expect(
      find.byKey(const Key('selection_toolbar_button_Remove')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('selection_toolbar_button_Save')),
      findsOneWidget,
    );
  });

  testWidgets('中文取消收藏在选区操作栏中保持单行', (tester) async {
    final dao = _RecordingSavedWordDao({'beta'});
    await tester.pumpWidget(
      wrap(
        locale: const Locale('zh'),
        overrides: [savedWordDaoProvider.overrideWithValue(dao)],
      ),
    );
    await tester.pumpAndSettle();
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('取消收藏'));
    expect(label.maxLines, 1);
    expect(label.softWrap, isFalse);
  });

  testWidgets('复制写入精确选区，并同步清除选区与词典面板', (tester) async {
    await tester.pumpWidget(wrap());
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict_sheet_sizer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection_toolbar_button_Copy')));
    await tester.pumpAndSettle();

    expect(clipboardText, 'beta');
    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    expect(editableState.textEditingValue.selection.isCollapsed, isTrue);
    expect(find.byKey(const Key('dict_sheet_sizer')), findsNothing);
  });

  testWidgets('拖选保持字符级自由边界，不吸附到完整单词', (tester) async {
    await tester.pumpWidget(wrap());
    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    final value = editableState.textEditingValue;
    const selection = TextSelection(baseOffset: 1, extentOffset: 8);
    editableState.userUpdateTextEditingValue(
      value.copyWith(selection: selection),
      SelectionChangedCause.drag,
    );
    await tester.pump();

    expect(editableState.textEditingValue.selection, selection);
    expect(selection.textInside(value.text), 'lpha be');
  });

  testWidgets('选区折叠时自动关闭当前句子的词典面板', (tester) async {
    await tester.pumpWidget(wrap());
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict_sheet_sizer')), findsOneWidget);

    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    editableState.userUpdateTextEditingValue(
      editableState.textEditingValue.copyWith(
        selection: const TextSelection.collapsed(offset: 0),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dict_sheet_sizer')), findsNothing);
  });

  testWidgets(
    'Android 长按期间不查词，松手后查询系统选中的单词',
    (tester) async {
      await tester.pumpWidget(wrap());
      final gesture = await tester.startGesture(wordCenter(tester, 'beta'));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(source.queries, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(source.queries, ['beta']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Android 长按统一触发选择轻反馈和平台长按反馈',
    (tester) async {
      await tester.pumpWidget(wrap());
      await tester.longPressAt(wordCenter(tester, 'beta'));
      await tester.pumpAndSettle();

      expect(hapticCalls, ['HapticFeedbackType.selectionClick', null]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'iOS 首次未聚焦和再次长按都触发相同反馈',
    (tester) async {
      await tester.pumpWidget(wrap());
      await tester.longPressAt(wordCenter(tester, 'beta'));
      await tester.pumpAndSettle();

      expect(hapticCalls, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.heavyImpact',
      ]);

      hapticCalls.clear();
      await tester.longPressAt(wordCenter(tester, 'gamma'));
      await tester.pumpAndSettle();
      expect(hapticCalls, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.heavyImpact',
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android 长按拖选期间不查词，松手后查询最终选区',
    (tester) async {
      await tester.pumpWidget(wrap());
      final gesture = await tester.startGesture(wordCenter(tester, 'alpha'));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(wordCenter(tester, 'gamma'));
      await tester.pump();
      expect(source.queries, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(source.queries, ['alpha beta gamma']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Android 长按取消不触发查词',
    (tester) async {
      await tester.pumpWidget(wrap());
      final gesture = await tester.startGesture(wordCenter(tester, 'beta'));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(source.queries, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('面板开着时：点句子里另一个词切换查询（豁免放行），点句子外空白关面板', (tester) async {
    await tester.pumpWidget(wrap());
    await tapWord(tester, 'alpha');
    await tester.pumpAndSettle();
    expect(source.queries, ['alpha']);

    // 点句子里另一个词：屏障豁免放行，切换查询、面板不关
    await tapWord(tester, 'gamma');
    await tester.pumpAndSettle();
    expect(source.queries, ['alpha', 'gamma']);
    expect(find.byKey(const Key('dict_sheet_sizer')), findsOneWidget);

    // 点句子外空白（正文中部）：屏障关面板并吸收点击
    await tester.tapAt(const Offset(400, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict_sheet_sizer')), findsNothing);
    // 未发起新查询
    expect(source.queries, ['alpha', 'gamma']);
  });

  testWidgets('面板开着时点句子紧邻上下的下层控件：关面板并吸收，不误触发下层交互', (tester) async {
    // 复现真机反馈：句子上方一小条区域点击触发了「隐藏字幕」、解析按钮
    // 被误触发——旧实现豁免区是组件 bounds 上下外扩 36dp 的粗矩形。
    var aboveTaps = 0;
    var belowTaps = 0;
    await tester.pumpWidget(
      wrap(
        layout: (sentence) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              key: const Key('above_area'),
              behavior: HitTestBehavior.opaque,
              onTap: () => aboveTaps++,
              child: const SizedBox(width: 600, height: 30),
            ),
            sentence,
            GestureDetector(
              key: const Key('below_area'),
              behavior: HitTestBehavior.opaque,
              onTap: () => belowTaps++,
              child: const SizedBox(width: 600, height: 30),
            ),
          ],
        ),
      ),
    );
    // 面板关闭时下层控件正常可点（取右侧远离手柄横坐标的点，下同）
    final abovePoint = Offset(
      500,
      tester.getRect(find.byKey(const Key('above_area'))).center.dy,
    );
    await tester.tapAt(abovePoint);
    expect(aboveTaps, 1);

    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict_sheet_sizer')), findsOneWidget);

    // 面板开着：点句子上方紧邻控件 → 屏障关面板并吸收，下层不触发
    await tester.tapAt(abovePoint);
    await tester.pumpAndSettle();
    expect(aboveTaps, 1);
    expect(find.byKey(const Key('dict_sheet_sizer')), findsNothing);

    // 再开面板：点句子下方紧邻控件同理
    await tapWord(tester, 'beta');
    await tester.pumpAndSettle();
    final belowPoint = Offset(
      500,
      tester.getRect(find.byKey(const Key('below_area'))).center.dy,
    );
    await tester.tapAt(belowPoint);
    await tester.pumpAndSettle();
    expect(belowTaps, 0);
    expect(find.byKey(const Key('dict_sheet_sizer')), findsNothing);
  });

  testWidgets('面板关闭后系统选区失去焦点', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.longPressAt(wordCenter(tester, 'beta'));
    await tester.pumpAndSettle();
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selectable.focusNode?.hasFocus, isTrue);

    hostKey.currentState!.close();
    await tester.pumpAndSettle();
    expect(selectable.focusNode?.hasFocus, isFalse);
  });

  testWidgets('评分片段染色仍生效（命中片段绿色）', (tester) async {
    await tester.pumpWidget(
      wrap(
        segments: const [
          SpeechTranscriptSegment(text: 'alpha ', isMatched: true),
          SpeechTranscriptSegment(text: 'beta gamma', isMatched: false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final spans = sentenceSpans(tester);
    // 首 token alpha 应为绿色
    expect(spans.first.text, 'alpha');
    expect(spans.first.style?.color, const Color(0xFF2E9B51));
    // beta 不染色
    final beta = spans.firstWhere((s) => s.text == 'beta');
    expect(beta.style?.color, isNull);
  });

  testWidgets('收藏单词渲染橙色点状下划线，未收藏词无标记', (tester) async {
    await tester.pumpWidget(
      wrap(
        overrides: [
          savedWordTextsProvider.overrideWith(
            () => _FakeSavedWordTexts({'beta'}),
          ),
        ],
      ),
    );
    await tester.pump(); // 等收藏集合流发射

    final spans = sentenceSpans(tester);
    final beta = spans.firstWhere((s) => s.text == 'beta');
    expect(beta.style?.decoration, TextDecoration.underline);
    expect(beta.style?.decorationStyle, TextDecorationStyle.dotted);
    expect(beta.style?.decorationColor, Colors.orange.shade400);
    final alpha = spans.firstWhere((s) => s.text == 'alpha');
    expect(alpha.style?.decoration, isNull);
  });

  testWidgets('收藏词组下划线连续横跨词间空白', (tester) async {
    await tester.pumpWidget(
      wrap(
        overrides: [
          savedWordTextsProvider.overrideWith(
            () => _FakeSavedWordTexts({'beta gamma'}),
          ),
        ],
      ),
    );
    await tester.pump();

    final spans = sentenceSpans(tester);
    // beta、词间空白、gamma 三个 span 都带下划线，alpha 及其后空白不带
    for (final text in ['beta', ' ', 'gamma']) {
      final span = spans.lastWhere((s) => s.text == text);
      expect(
        span.style?.decoration,
        TextDecoration.underline,
        reason: 'span "$text" 应带下划线',
      );
    }
    final alpha = spans.firstWhere((s) => s.text == 'alpha');
    expect(alpha.style?.decoration, isNull);
    final firstSpace = spans.firstWhere((s) => s.text == ' ');
    expect(firstSpace.style?.decoration, isNull);
  });

  testWidgets('收藏意群（normalizeSenseGroupPhrase 规则）也命中标记', (tester) async {
    await tester.pumpWidget(
      wrap(
        overrides: [
          savedSenseGroupTextsProvider.overrideWith(
            () => _FakeSavedSenseGroupTexts({'alpha beta'}),
          ),
        ],
      ),
    );
    await tester.pump();

    final spans = sentenceSpans(tester);
    expect(
      spans.firstWhere((s) => s.text == 'alpha').style?.decoration,
      TextDecoration.underline,
    );
    expect(
      spans.firstWhere((s) => s.text == 'beta').style?.decoration,
      TextDecoration.underline,
    );
    expect(
      spans.firstWhere((s) => s.text == 'gamma').style?.decoration,
      isNull,
    );
  });

  testWidgets('收藏下划线与评分染色可同时渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        segments: const [
          SpeechTranscriptSegment(text: 'alpha ', isMatched: true),
          SpeechTranscriptSegment(text: 'beta gamma', isMatched: false),
        ],
        overrides: [
          savedWordTextsProvider.overrideWith(
            () => _FakeSavedWordTexts({'alpha'}),
          ),
        ],
      ),
    );
    await tester.pump();

    final alpha = sentenceSpans(tester).firstWhere((s) => s.text == 'alpha');
    expect(alpha.style?.color, const Color(0xFF2E9B51));
    expect(alpha.style?.decoration, TextDecoration.underline);
  });
}
