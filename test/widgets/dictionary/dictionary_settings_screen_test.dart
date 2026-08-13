import 'package:dio/dio.dart';
import 'package:echo_loop/features/onboarding_survey/providers/onboarding_survey_provider.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/models/dictionary/dictionary_lookup_result.dart';
import 'package:echo_loop/providers/dictionary/dictionary_registry.dart';
import 'package:echo_loop/providers/dictionary/dictionary_settings_provider.dart';
import 'package:echo_loop/providers/pronunciation/pronunciation_providers.dart';
import 'package:echo_loop/screens/dictionary_settings_screen.dart';
import 'package:echo_loop/services/dictionary/dictionary_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource implements DictionarySource {
  @override
  final String id;
  @override
  final bool canBeDisabled;
  _FakeSource(this.id, {required this.canBeDisabled});
  @override
  IconData get icon => Icons.abc;
  @override
  bool get requiresNetwork => false;
  @override
  Future<DictionaryLookupResult?> lookup(
    DictionaryLookupRequest request, {
    CancelToken? cancelToken,
  }) async => null;
}

class _TestPronunciationLibraryNotifier extends PronunciationLibraryNotifier {
  _TestPronunciationLibraryNotifier(this.initialState);

  final PronunciationLibraryState initialState;
  int retryCalls = 0;
  int redownloadCalls = 0;

  @override
  PronunciationLibraryState build() => initialState;

  @override
  Future<void> retryDownload() async {
    retryCalls += 1;
  }

  @override
  Future<void> redownload() async {
    redownloadCalls += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  final fakeSources = <DictionarySource>[
    _FakeSource('local', canBeDisabled: false),
    _FakeSource('ai', canBeDisabled: false),
    _FakeSource('cambridge', canBeDisabled: true),
  ];

  (ProviderContainer, Widget, _TestPronunciationLibraryNotifier) build({
    PronunciationLibraryState pronunciationState =
        const PronunciationLibraryState(),
  }) {
    final pronunciationNotifier = _TestPronunciationLibraryNotifier(
      pronunciationState,
    );
    final container = ProviderContainer(
      overrides: [
        dictionarySourcesProvider.overrideWithValue(fakeSources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        pronunciationLibraryProvider.overrideWith(() => pronunciationNotifier),
      ],
    );
    addTearDown(container.dispose);
    return (
      container,
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en'), Locale('zh')],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: DictionarySettingsScreen(),
        ),
      ),
      pronunciationNotifier,
    );
  }

  testWidgets('本地/AI 锁定，Cambridge 可开关', (tester) async {
    final (_, widget, _) = build();
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // local + ai 显示「Always on」锁定
    expect(find.text('Always on'), findsNWidgets(2));
    // cambridge 一个 Switch
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('切换默认词典', (tester) async {
    final (container, widget, _) = build();
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(
      container.read(dictionarySettingsNotifierProvider).defaultSourceId,
      'local',
    );
    // 默认区在前，首个 'AI Dictionary' 即默认区项
    await tester.tap(find.text('AI Dictionary').first);
    await tester.pumpAndSettle();
    expect(
      container.read(dictionarySettingsNotifierProvider).defaultSourceId,
      'ai',
    );
  });

  testWidgets('禁用 Cambridge → 移出默认区选项', (tester) async {
    final (container, widget, _) = build();
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // 初始：默认区 + 词典源区各一个 Cambridge
    expect(find.text('Cambridge'), findsNWidgets(2));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(container.read(dictionarySettingsNotifierProvider).disabledIds, {
      'cambridge',
    });
    // 默认区不再列出 Cambridge，仅词典源区保留
    expect(find.text('Cambridge'), findsOneWidget);
  });

  testWidgets('离线发音库已就绪时显示用途、大小和重新下载按钮', (tester) async {
    final (_, widget, notifier) = build(
      pronunciationState: const PronunciationLibraryState(
        status: PronunciationLibraryStatus.ready,
        localSizeBytes: 39426457,
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('Offline Word Pronunciation'), findsOneWidget);
    expect(
      find.text('Pre-recorded word audio for dictionary lookups'),
      findsOneWidget,
    );
    final description = tester.widget<Text>(
      find.text('Pre-recorded word audio for dictionary lookups'),
    );
    expect(description.style?.fontSize, 12);
    expect(
      find.ancestor(
        of: find.text('Pre-recorded word audio for dictionary lookups'),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
    expect(find.text('37.6 MB'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Download again'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Download again'));
    expect(notifier.redownloadCalls, 1);
  });

  testWidgets('离线发音库下载中显示紧凑进度', (tester) async {
    final (_, widget, _) = build(
      pronunciationState: const PronunciationLibraryState(
        status: PronunciationLibraryStatus.downloading,
        progress: 0.5,
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, 0.5);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('离线发音库失败时提供重试按钮', (tester) async {
    final (_, widget, notifier) = build(
      pronunciationState: const PronunciationLibraryState(
        status: PronunciationLibraryStatus.failed,
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    expect(notifier.retryCalls, 1);
  });
}
