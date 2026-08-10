import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:echo_loop/features/official_collections/data/official_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/catalog_fixtures.dart';

/// 用 Dio 的 transformer 注入：每次拿不同/相同 body 模拟后端响应。
class _MockDio extends Fake implements Dio {
  int callCount = 0;
  Object? throwOnNext;
  late String Function() bodyProvider;

  _MockDio({required this.bodyProvider});

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    callCount++;
    final t = throwOnNext;
    if (t != null) {
      throwOnNext = null;
      throw t;
    }
    final body = bodyProvider();
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('catalog_svc_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('节流 2h 内 outcome=throttled，dio 不发请求', () async {
    final body = snapshotToBody(
      makeSnapshot(collections: [makeCatalogCollection()]),
    );
    final dio = _MockDio(bodyProvider: () => body);
    final svc = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );

    // 第一次 refresh：updated（首次拉）
    final first = await svc.refresh();
    expect(first, isA<CatalogUpdated>());
    expect(dio.callCount, 1);

    // 立即第二次：节流命中，连请求都不发
    final second = await svc.refresh();
    expect(second, isA<CatalogThrottled>());
    expect(dio.callCount, 1, reason: '节流期间 dio 不应被调');
  });

  test('force=true 绕过节流，仍发请求', () async {
    final body = snapshotToBody(
      makeSnapshot(collections: [makeCatalogCollection()]),
    );
    final dio = _MockDio(bodyProvider: () => body);
    final svc = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );

    await svc.refresh();
    expect(dio.callCount, 1);

    final result = await svc.refresh(force: true);
    expect(dio.callCount, 2);
    // body 一致 → unchanged
    expect(result, isA<CatalogUnchanged>());
  });

  test('远端返回相同 body → outcome=unchanged，catalog.json 文件 mtime 不变', () async {
    final body = snapshotToBody(
      makeSnapshot(collections: [makeCatalogCollection()]),
    );
    final dio = _MockDio(bodyProvider: () => body);
    final svc = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );

    await svc.refresh();
    final catalogFile = File('${tempDir.path}/catalog.json');
    final mtimeBefore = (await catalogFile.stat()).modified;

    // 等一点点确保 mtime 颗粒度足够
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final outcome = await svc.refresh(force: true);
    expect(outcome, isA<CatalogUnchanged>());
    final mtimeAfter = (await catalogFile.stat()).modified;
    expect(mtimeAfter, mtimeBefore, reason: 'unchanged 时不应重写 catalog.json');
  });

  test('远端返回不同 body → outcome=updated，文件被改写', () async {
    var version = 1;
    final dio = _MockDio(
      bodyProvider: () {
        final c = makeCatalogCollection(id: 'r-coll', name: 'v$version');
        version++;
        return snapshotToBody(makeSnapshot(collections: [c]));
      },
    );
    final svc = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );

    final first = await svc.refresh();
    expect(first, isA<CatalogUpdated>());
    final hashBefore = (first as CatalogUpdated).snapshot.contentHash;

    final second = await svc.refresh(force: true);
    expect(second, isA<CatalogUpdated>());
    final hashAfter = (second as CatalogUpdated).snapshot.contentHash;
    expect(hashAfter, isNot(hashBefore), reason: 'body 不同 → hash 不同');
  });

  test('远端 catalog 解析并缓存 podcastCatalogs', () async {
    final body = snapshotToBody(
      makeSnapshot(
        collections: [makeCatalogCollection()],
        podcastCatalogs: [
          makeCatalogPodcast(id: 'podcast-1', title: '6 Minute English'),
        ],
      ),
    );
    final dio = _MockDio(bodyProvider: () => body);
    final svc = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );

    final outcome = await svc.refresh();
    expect(outcome, isA<CatalogUpdated>());
    expect(svc.cached?.podcastCatalogs, hasLength(1));
    expect(svc.cached?.podcastCatalogs.single.title, '6 Minute English');

    final reloaded = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );
    final cached = await reloaded.loadCachedCatalog();
    expect(cached?.podcastCatalogs.single.rssUrl, contains('p02pc9tn.rss'));
  });

  test('CatalogPodcast 订阅输入 URL 优先保留 Apple Podcasts 链接', () {
    final withApple = makeCatalogPodcast(
      applePodcastUrl:
          ' https://podcasts.apple.com/us/podcast/6-minute-english/id262026947 ',
      rssUrl: ' https://podcasts.files.bbci.co.uk/p02pc9tn.rss ',
    );
    final rssOnly = makeCatalogPodcast(
      applePodcastUrl: ' ',
      rssUrl: ' https://podcasts.files.bbci.co.uk/p02pc9tn.rss ',
    );

    expect(
      withApple.subscriptionInputUrl,
      'https://podcasts.apple.com/us/podcast/6-minute-english/id262026947',
    );
    expect(
      rssOnly.subscriptionInputUrl,
      'https://podcasts.files.bbci.co.uk/p02pc9tn.rss',
    );
  });

  test('旧 catalog body 缺少 podcastCatalogs 时按空列表兼容', () async {
    const body = '''
{
  "serverTime":"2026-04-19T00:00:00.000Z",
  "collections":[]
}
''';
    final dio = _MockDio(bodyProvider: () => body);
    final svc = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );

    final outcome = await svc.refresh();
    expect(outcome, isA<CatalogUpdated>());
    expect(svc.cached?.podcastCatalogs, isEmpty);
  });

  test('远端抛错 → outcome=failed，本地文件保留', () async {
    final body = snapshotToBody(
      makeSnapshot(collections: [makeCatalogCollection()]),
    );
    final dio = _MockDio(bodyProvider: () => body);
    final svc = OfficialCatalogService.withDio(
      dio: dio,
      resolveDir: () async => tempDir,
    );

    // 首次成功
    await svc.refresh();
    final catalogFile = File('${tempDir.path}/catalog.json');
    final bodyBefore = await catalogFile.readAsString();

    // 第二次：网络挂了
    dio.throwOnNext = StateError('boom');
    final outcome = await svc.refresh(force: true);
    expect(outcome, isA<CatalogFailed>());

    // 本地文件保留
    final bodyAfter = await catalogFile.readAsString();
    expect(bodyAfter, bodyBefore);
    expect(svc.cached, isNotNull, reason: '失败不应擦除已有 cached');
  });

  test('并发 refresh 复用 inflight：连发 3 次只算 1 次 dio 请求', () async {
    final completer = Completer<String>();
    final body = snapshotToBody(
      makeSnapshot(collections: [makeCatalogCollection()]),
    );
    // 改写 get 让首次挂起
    final waitDio = _SlowDio(body: body, gate: completer.future);
    final svc = OfficialCatalogService.withDio(
      dio: waitDio,
      resolveDir: () async => tempDir,
    );

    final f1 = svc.refresh();
    final f2 = svc.refresh();
    final f3 = svc.refresh(force: true);

    // 触发 dio 真正返回
    completer.complete(body);
    final results = await Future.wait([f1, f2, f3]);

    // dio 实际只被调 1 次
    expect(waitDio.callCount, 1);
    // 三个 future 拿到同一个 outcome（updated 或 unchanged 取决于内部）
    expect(results[0].runtimeType, results[1].runtimeType);
    expect(results[1].runtimeType, results[2].runtimeType);
  });
}

class _SlowDio extends Fake implements Dio {
  int callCount = 0;
  final String body;
  final Future<dynamic> gate;

  _SlowDio({required this.body, required this.gate});

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    callCount++;
    await gate;
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}
