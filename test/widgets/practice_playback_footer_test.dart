import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/widgets/common/practice_playback_footer.dart';
import 'package:echo_loop/widgets/practice/practice_play_count_label.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('移动端学习页底部控制区完整避让系统安全区', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      createTestApp(
        Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context)!;
            return Column(
              children: [
                const Spacer(),
                PracticePlaybackFooter(
                  canGoPrev: true,
                  isLast: false,
                  centerIcon: Icons.play_arrow_rounded,
                  onPrevious: () {},
                  onNext: () {},
                  onCenter: () {},
                  isManualMode: false,
                  playCountText: formatPracticePlayCount(
                    l10n,
                    currentCount: 1,
                    totalCount: 1,
                  ),
                  statusSuffixText: '1.0x',
                  l10n: l10n,
                  theme: Theme.of(context),
                ),
              ],
            );
          },
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pump();

    final labelBottom = tester
        .getRect(find.byKey(kPracticePlaybackFooterLabelKey))
        .bottom;
    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // footer 的播放按钮和 label 统一避让底部系统区域，不再只给 label 留半个 inset。
    expect(screenBottom - labelBottom, closeTo(34, 0.1));
  });

  testWidgets('支持替换右侧下一句控件', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        Builder(
          builder: (context) => PracticePlaybackFooter(
            canGoPrev: true,
            isLast: false,
            centerIcon: Icons.play_arrow_rounded,
            onPrevious: () {},
            onNext: () {},
            onCenter: () {},
            nextControl: const Text('继续'),
            isManualMode: false,
            playCountText: '1/1',
            l10n: AppLocalizations.of(context)!,
            theme: Theme.of(context),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('继续'), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
  });
}
