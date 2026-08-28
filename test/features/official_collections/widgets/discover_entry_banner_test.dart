import 'package:echo_loop/features/official_collections/widgets/discover_entry_banner.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/models/collection.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 轻量 CollectionList override：只控制 `state`，不接 DB。
class _FakeCollectionList extends CollectionList {
  final List<Collection> _seed;
  _FakeCollectionList(this._seed);

  @override
  CollectionState build() {
    return CollectionState(rawCollections: _seed, isLoading: false);
  }
}

Collection _officialCollection(int i) => Collection(
  id: 'c$i',
  name: 'Official $i',
  createdDate: DateTime(2026, 1, 1),
  source: CollectionSource.official,
  remoteId: 'r$i',
);

Widget _host({required List<Collection> collections, VoidCallback? onTap}) {
  return ProviderScope(
    overrides: [
      collectionListProvider.overrideWith(
        () => _FakeCollectionList(collections),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh', 'CN'),
      home: Scaffold(body: DiscoverEntryBanner(onTap: onTap)),
    ),
  );
}

void main() {
  testWidgets('入口卡片：固定显示「发现资源 / 播客、托福、…」', (tester) async {
    await tester.pumpWidget(_host(collections: const []));
    await tester.pumpAndSettle();

    expect(find.text('发现资源'), findsOneWidget);
    expect(find.text('播客、托福、雅思、四六级、口译...'), findsOneWidget);
    // 旧 B 态文案不应再出现
    expect(find.text('看看新上架'), findsNothing);
  });

  testWidgets('入口卡片：已加入若干官方合集后文案不切换', (tester) async {
    await tester.pumpWidget(
      _host(
        collections: [
          _officialCollection(1),
          _officialCollection(2),
          _officialCollection(3),
          _officialCollection(4),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现资源'), findsOneWidget);
    expect(find.text('看看新上架'), findsNothing);
  });

  testWidgets('点击整卡触发 onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _host(collections: const [], onTap: () => tapped++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell));
    expect(tapped, 1);
  });
}
