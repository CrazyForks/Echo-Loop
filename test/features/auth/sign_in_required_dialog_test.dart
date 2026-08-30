import 'package:echo_loop/features/auth/providers/auth_providers.dart';
import 'package:echo_loop/features/auth/sign_in_required_dialog.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('显式登录入口直接打开登录页，不显示登录原因弹窗', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => openSignInPage(context),
                child: const Text('Sign In'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const Scaffold(body: Text('Login page')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Login page'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('未登录时可取消或进入登录页，且不继续原操作', (tester) async {
    var continued = false;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Consumer(
              builder: (context, ref, child) => FilledButton(
                onPressed: () async {
                  continued = await ensureSignedInForAction(
                    context: context,
                    ref: ref,
                    title: 'Sign in required',
                    message: 'Please sign in first.',
                  );
                },
                child: const Text('Protected action'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const Scaffold(body: Text('Login page')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isAuthenticatedProvider.overrideWithValue(false)],
        child: MaterialApp.router(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Protected action'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(continued, isFalse);
    expect(find.text('Protected action'), findsOneWidget);

    await tester.tap(find.text('Protected action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(continued, isFalse);
    expect(find.text('Login page'), findsOneWidget);
  });

  testWidgets('已登录时直接继续原操作', (tester) async {
    var continued = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isAuthenticatedProvider.overrideWithValue(true)],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) => FilledButton(
                onPressed: () async {
                  continued = await ensureSignedInForAction(
                    context: context,
                    ref: ref,
                    title: 'Sign in required',
                    message: 'Please sign in first.',
                  );
                },
                child: const Text('Protected action'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Protected action'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    expect(find.text('Sign in required'), findsNothing);
  });
}
