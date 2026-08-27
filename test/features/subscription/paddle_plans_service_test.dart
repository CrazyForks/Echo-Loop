import 'dart:io';

import 'package:dio/dio.dart';
import 'package:echo_loop/features/subscription/services/paddle_plans_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this.data);

  final Map<String, dynamic> data;
  int callCount = 0;

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
    return Response<T>(
      data: this.data as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paddle_plans_svc_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('persist=false 不写磁盘，内容未变化时仍返回 unchanged', () async {
    final dio = _FakeDio({'plans': []});
    var resolveCount = 0;
    final service = PaddlePlansService(
      dio: dio,
      persist: false,
      resolveDir: () async {
        resolveCount++;
        return tempDir;
      },
    );

    expect(await service.refresh(), isA<PaddlePlansUpdated>());
    expect(await service.refresh(force: true), isA<PaddlePlansUnchanged>());
    expect(dio.callCount, 2);
    expect(resolveCount, 0);
    expect(await tempDir.list().toList(), isEmpty);
  });

  test('unchanged 时 meta 写失败仍更新时间并继续节流', () async {
    final dio = _FakeDio({'plans': []});
    var resolveCount = 0;
    final blocker = File('${tempDir.path}/not_a_directory');
    final service = PaddlePlansService(
      dio: dio,
      resolveDir: () async {
        resolveCount++;
        if (resolveCount <= 3) return tempDir;
        return Directory(blocker.path);
      },
    );

    expect(await service.refresh(), isA<PaddlePlansUpdated>());
    await blocker.writeAsString('blocker');

    expect(await service.refresh(force: true), isA<PaddlePlansUnchanged>());
    expect(await service.refresh(), isA<PaddlePlansThrottled>());
    expect(dio.callCount, 2);
  });
}
