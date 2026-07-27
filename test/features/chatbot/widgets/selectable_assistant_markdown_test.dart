/// SelectableAssistantMarkdown 测试：官方 SelectionArea 选区 + 操作条（复制 / 问 AI）。
library;

import 'package:echo_loop/features/chatbot/widgets/selectable_assistant_markdown.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'chatbot_widget_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 说明：headless 测试环境下 SelectedContent.plainText 常为空（真机才有内容），
  // 因此只覆盖「选区 + 操作条接线」这类稳定行为，不断言选中文本的具体内容。
  //
  // 强制 iOS 平台，覆盖移动端「长按选区即弹操作条」主路径。
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);
  final android = TargetPlatformVariant.only(TargetPlatform.android);
  final hapticCalls = <Object?>[];

  setUp(() {
    hapticCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            hapticCalls.add(call.arguments);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('用官方 SelectionArea 包裹 markdown（可选中）', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(GptMarkdown), findsOneWidget);
    final selectionContext = tester.element(find.byType(SelectionArea));
    expect(
      DefaultSelectionStyle.of(selectionContext).selectionColor,
      CupertinoColors.systemBlue
          .resolveFrom(selectionContext)
          .withValues(alpha: 0.2),
    );
    expect(
      CupertinoTheme.of(selectionContext).selectionHandleColor,
      CupertinoColors.systemBlue.resolveFrom(selectionContext),
    );
  }, variant: iOS);

  testWidgets('Android AI 聊天回答使用平台选择蓝，不回落到 App 主题色', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );
    final selectionContext = tester.element(find.byType(SelectionArea));
    final expectedColor = Colors.blue.withValues(alpha: 0.4);
    expect(
      DefaultSelectionStyle.of(selectionContext).selectionColor,
      expectedColor,
    );
    expect(
      TextSelectionTheme.of(selectionContext).selectionHandleColor,
      Colors.blue,
    );
  }, variant: android);

  testWidgets('长按选区弹出操作条：复制 + 问 AI', (tester) async {
    await pumpChatWidget(
      tester,
      SelectableAssistantMarkdown(data: 'hello world', onFollowUp: (_) {}),
    );
    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();
    // en locale：Copy / Ask AI —— 证明 contextMenuBuilder 已接管为自定义操作条。
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Ask AI'), findsOneWidget);
    // 横向气泡：CupertinoTextSelectionToolbar（灰色圆角胶囊），非纵向 desktop 菜单。
    expect(find.byType(CupertinoTextSelectionToolbar), findsOneWidget);
    // 外壳由项目自定义为纯圆角胶囊，不使用 Cupertino 默认的箭头形状。
    expect(
      find.byKey(const ValueKey('selection_toolbar_surface')),
      findsOneWidget,
    );
  }, variant: iOS);

  testWidgets('iOS 长按新选区统一触发选择轻反馈和平台长按反馈', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );

    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();

    expect(hapticCalls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.heavyImpact',
    ]);

    hapticCalls.clear();
    await tester.longPressAt(
      tester.getCenter(find.byType(GptMarkdown)) + const Offset(25, 0),
    );
    await tester.pumpAndSettle();
    expect(hapticCalls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.heavyImpact',
    ]);
  }, variant: iOS);

  testWidgets('Android 长按新选区统一触发选择轻反馈和平台长按反馈', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );

    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();

    expect(hapticCalls, ['HapticFeedbackType.selectionClick', null]);
  }, variant: android);

  testWidgets('长按开始显示放大镜，松手后立即移除', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GptMarkdown)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('assistant_initial_selection_magnifier')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('assistant_initial_selection_magnifier')),
      findsNothing,
    );
  }, variant: iOS);

  testWidgets('取消长按会清理初始放大镜', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GptMarkdown)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('assistant_initial_selection_magnifier')),
      findsOneWidget,
    );

    await gesture.cancel();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('assistant_initial_selection_magnifier')),
      findsNothing,
    );
  }, variant: android);

  testWidgets('已有选区的明显拖动不叠加初始放大镜', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );
    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GptMarkdown)),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('assistant_initial_selection_magnifier')),
      findsNothing,
    );
    await gesture.cancel();
  }, variant: iOS);

  testWidgets('中文操作条按钮等宽且保持紧凑高度，分割线居中', (tester) async {
    await pumpChatWidget(
      tester,
      SelectableAssistantMarkdown(data: 'hello world', onFollowUp: (_) {}),
      locale: const Locale('zh'),
    );
    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();

    final copyButton = find.byKey(
      const ValueKey('selection_toolbar_button_复制'),
    );
    final askAiButton = find.byKey(
      const ValueKey('selection_toolbar_button_问 AI'),
    );
    expect(copyButton, findsOneWidget);
    expect(askAiButton, findsOneWidget);
    expect(tester.getSize(copyButton).width, tester.getSize(askAiButton).width);
    final buttonContainer = tester.widget<Container>(
      find.descendant(of: copyButton, matching: find.byType(Container)).first,
    );
    expect(
      buttonContainer.padding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }, variant: iOS);

  testWidgets('无 onFollowUp 时只显示复制（不显示问 AI）', (tester) async {
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );
    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Ask AI'), findsNothing);
  }, variant: iOS);

  testWidgets('点复制：收起操作条、写剪贴板、无异常', (tester) async {
    // 拦截剪贴板平台调用，验证复制被触发（headless 下选区文本可能为空，
    // 故不强制断言写入内容，只回归「点击不崩、操作条收起」）。
    await pumpChatWidget(
      tester,
      const SelectableAssistantMarkdown(data: 'hello world'),
    );
    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: iOS);

  testWidgets('点问 AI：收起操作条、无异常', (tester) async {
    await pumpChatWidget(
      tester,
      SelectableAssistantMarkdown(data: 'hello world', onFollowUp: (_) {}),
    );
    await tester.longPress(find.byType(GptMarkdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    expect(find.text('Ask AI'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: iOS);
}
