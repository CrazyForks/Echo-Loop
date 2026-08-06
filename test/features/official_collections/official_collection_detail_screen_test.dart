import 'dart:io';

import 'package:dio/dio.dart';
import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/features/auth/providers/auth_providers.dart';
import 'package:echo_loop/features/official_collections/data/official_catalog_service.dart';
import 'package:echo_loop/features/official_collections/data/official_sync_service.dart';
import 'package:echo_loop/features/official_collections/models/catalog.dart';
import 'package:echo_loop/features/official_collections/screens/official_collection_detail_screen.dart';
import 'package:echo_loop/providers/audio_engine/audio_engine_provider.dart';
import 'package:echo_loop/providers/audio_library_provider.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:echo_loop/providers/learning_progress_provider.dart';
import 'package:echo_loop/providers/learning_session/blind_listen_player_provider.dart';
import 'package:echo_loop/providers/learning_session/learning_session_provider.dart';
import 'package:echo_loop/providers/listening_practice/listening_practice_provider.dart';
import 'package:echo_loop/providers/settings_provider.dart';
import 'package:echo_loop/providers/tag_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mock_providers.dart';
import '../../helpers/test_app.dart';
import 'fixtures/catalog_fixtures.dart';

class _FakeCatalogService extends OfficialCatalogService {
  final CatalogSnapshot? snapshot;

  _FakeCatalogService(this.snapshot)
    : super.withDio(dio: Dio(), resolveDir: () async => Directory.systemTemp);

  @override
  CatalogSnapshot? get cached => snapshot;

  @override
  bool get hasInitialized => true;
}

class _FakeAppDatabase extends Fake implements db.AppDatabase {}

class _NoopOfficialSyncService extends OfficialSyncService {
  _NoopOfficialSyncService(OfficialCatalogService catalog)
    : super(database: _FakeAppDatabase(), catalog: catalog);

  @override
  Future<OfficialSyncStats> syncAll({bool force = false}) async {
    return OfficialSyncStats.noop(const CatalogThrottled());
  }
}

Override _noopSyncOverride() {
  return officialSyncServiceProvider.overrideWith(
    (ref) => _NoopOfficialSyncService(ref.read(officialCatalogServiceProvider)),
  );
}

void main() {
  testWidgets('未加入官方空合集详情页仍保留可下拉刷新的滚动区域', (tester) async {
    final snapshot = makeSnapshot(
      collections: [
        makeCatalogCollection(
          id: 'empty-official',
          name: 'Empty Official',
          audios: const [],
        ),
      ],
    );

    await tester.pumpWidget(
      createTestApp(
        const OfficialCollectionDetailScreen(remoteId: 'empty-official'),
        overrides: [
          appSettingsProvider.overrideWith(
            () => TestAppSettings(const AppSettingsState()),
          ),
          officialCatalogServiceProvider.overrideWithValue(
            _FakeCatalogService(snapshot),
          ),
          audioLibraryProvider.overrideWith(() => TestAudioLibrary()),
          collectionListProvider.overrideWith(() => TestCollectionList()),
          tagListProvider.overrideWith(() => TestTagList()),
          listeningPracticeProvider.overrideWith(() => TestListeningPractice()),
          audioEngineProvider.overrideWith(() => TestAudioEngine()),
          learningProgressNotifierProvider.overrideWith(
            () => TestLearningProgressNotifier(),
          ),
          learningSessionProvider.overrideWith(() => TestLearningSession()),
          blindListenPlayerProvider.overrideWith(() => TestBlindListenPlayer()),
          _noopSyncOverride(),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('This collection has no audios yet'), findsOneWidget);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<AlwaysScrollableScrollPhysics>());
  });

  testWidgets('未登录点击详情页添加按钮时先显示登录提示', (tester) async {
    final snapshot = makeSnapshot(
      collections: [
        makeCatalogCollection(
          id: 'official-1',
          name: 'Official Collection',
          audios: [makeCatalogAudio()],
        ),
      ],
    );

    await tester.pumpWidget(
      createTestApp(
        const OfficialCollectionDetailScreen(remoteId: 'official-1'),
        overrides: [
          officialCatalogServiceProvider.overrideWithValue(
            _FakeCatalogService(snapshot),
          ),
          isAuthenticatedProvider.overrideWithValue(false),
          _noopSyncOverride(),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to My Collections'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to add collections'), findsOneWidget);
    expect(
      find.textContaining('Sign in to add curated collections'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('未登录从详情音频确认添加时使用相同登录提示', (tester) async {
    final snapshot = makeSnapshot(
      collections: [
        makeCatalogCollection(
          id: 'official-1',
          name: 'Official Collection',
          audios: [makeCatalogAudio(title: 'Track 1')],
        ),
      ],
    );

    await tester.pumpWidget(
      createTestApp(
        const OfficialCollectionDetailScreen(remoteId: 'official-1'),
        overrides: [
          officialCatalogServiceProvider.overrideWithValue(
            _FakeCatalogService(snapshot),
          ),
          isAuthenticatedProvider.overrideWithValue(false),
          _noopSyncOverride(),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Track 1'));
    await tester.pumpAndSettle();
    expect(find.text('Add Collection First'), findsOneWidget);

    await tester.tap(find.text('Add to My Collections').last);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to add collections'), findsOneWidget);
    expect(find.text('Add Collection First'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
