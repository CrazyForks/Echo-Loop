/// 百度网盘文件 API 客户端。
///
/// 只访问百度开放平台域名，不复用自家后端 Dio。请求统一把 access_token 放在
/// query 中，并由 ApiLogInterceptor 脱敏，避免凭据进入开发者日志。
library;

import 'package:dio/dio.dart';

import '../../../services/api_log_interceptor.dart';
import '../../../services/reliable_http_downloader.dart';
import '../models/cloud_drive_models.dart';
import '../models/baidu_account_profile.dart';

/// 百度网盘文件 API 抽象。
abstract interface class BaiduNetdiskApi {
  /// 获取当前授权账户资料。
  Future<BaiduAccountProfile> fetchAccountProfile({
    required String accessToken,
  });

  /// 列出目录。
  Future<CloudDriveListPage> listDirectory({
    required String accessToken,
    String dir = '/',
    int start = 0,
    int limit = 100,
  });

  /// 获取文件下载 dlink。
  Future<BaiduDownloadLink> fetchDownloadLink({
    required String accessToken,
    required int fsId,
  });

  /// 下载 dlink 到本地文件。
  Future<void> downloadToFile({
    required String accessToken,
    required String dlink,
    required String savePath,
    String? identityKey,
    int? expectedSize,
    bool allowResume = true,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  });
}

/// 默认百度网盘文件 API 实现。
class DefaultBaiduNetdiskApi implements BaiduNetdiskApi {
  /// 构造默认实现。
  DefaultBaiduNetdiskApi({
    Dio? metadataDio,
    Dio? profileDio,
    Dio? downloadDio,
    ReliableHttpDownloader? downloader,
  }) : _metadataDio = metadataDio ?? _createMetadataDio(),
       _profileDio = profileDio ?? _createProfileDio(),
       _downloader =
           downloader ??
           DioReliableHttpDownloader(dio: downloadDio ?? _createDownloadDio());

  final Dio _metadataDio;
  final Dio _profileDio;
  final ReliableHttpDownloader _downloader;

  static Dio _createBaiduDio({
    required bool enableLogging,
    String logTag = 'BAIDU-NETDISK',
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://pan.baidu.com',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'User-Agent': _baiduUserAgent},
      ),
    );
    if (enableLogging) {
      dio.interceptors.add(ApiLogInterceptor(tag: logTag));
    }
    return dio;
  }

  static Dio _createMetadataDio() => _createBaiduDio(enableLogging: true);

  static Dio _createDownloadDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        headers: const {'User-Agent': _baiduUserAgent},
      ),
    );
    dio.interceptors.add(ApiLogInterceptor(tag: 'BAIDU-DOWNLOAD'));
    return dio;
  }

  static Dio _createProfileDio() => _createBaiduDio(enableLogging: false);

  @override
  Future<BaiduAccountProfile> fetchAccountProfile({
    required String accessToken,
  }) async {
    final data = await _getJson(
      _profileDio,
      '/rest/2.0/xpan/nas',
      queryParameters: <String, Object?>{
        'method': 'uinfo',
        'access_token': accessToken,
      },
    );
    return BaiduAccountProfile.fromBaiduJson(data);
  }

  @override
  Future<CloudDriveListPage> listDirectory({
    required String accessToken,
    String dir = '/',
    int start = 0,
    int limit = 100,
  }) async {
    final normalizedLimit = limit.clamp(1, 1000);
    final data = await _getJson(
      _metadataDio,
      '/rest/2.0/xpan/file',
      queryParameters: <String, Object?>{
        'method': 'list',
        'access_token': accessToken,
        'dir': dir.isEmpty ? '/' : dir,
        'order': 'name',
        'start': start < 0 ? 0 : start,
        'limit': normalizedLimit,
        'web': 1,
        'folder': 0,
        'desc': 0,
      },
    );
    final list = data['list'];
    if (list is! List) {
      throw const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.unknown,
        message: 'Baidu list response is missing file list.',
      );
    }
    final entries = list
        .whereType<Map>()
        .map(CloudDriveEntry.fromBaiduJson)
        .toList(growable: false);
    return CloudDriveListPage(
      entries: entries,
      nextStart: (start < 0 ? 0 : start) + entries.length,
      hasMore: entries.length >= normalizedLimit,
    );
  }

  @override
  Future<BaiduDownloadLink> fetchDownloadLink({
    required String accessToken,
    required int fsId,
  }) async {
    final data = await _getJson(
      _metadataDio,
      '/rest/2.0/xpan/multimedia',
      queryParameters: <String, Object?>{
        'method': 'filemetas',
        'access_token': accessToken,
        'fsids': '[$fsId]',
        'dlink': 1,
      },
    );
    final list = data['list'];
    if (list is! List || list.isEmpty || list.first is! Map) {
      throw const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.notFound,
        message: 'Baidu download link is unavailable.',
      );
    }
    final link = BaiduDownloadLink.fromBaiduJson(list.first as Map);
    if (link.dlink.isEmpty) {
      throw const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.notFound,
        message: 'Baidu download link is empty.',
      );
    }
    return link;
  }

  @override
  Future<void> downloadToFile({
    required String accessToken,
    required String dlink,
    required String savePath,
    String? identityKey,
    int? expectedSize,
    bool allowResume = true,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final uri = Uri.parse(dlink);
    final downloadUri = uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'access_token': accessToken,
      },
    );
    try {
      await _downloader.download(
        uri: downloadUri,
        savePath: savePath,
        headers: const {'User-Agent': _baiduUserAgent},
        identityKey: identityKey,
        expectedSize: expectedSize,
        allowResume: allowResume,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    } on DioException catch (error) {
      throw _mapDioException(error, fallbackMessage: 'Baidu download failed.');
    } on ReliableDownloadException catch (error) {
      throw _mapReliableDownloadException(
        error,
        fallbackMessage: 'Baidu download failed.',
      );
    }
  }

  Future<Map<dynamic, dynamic>> _getJson(
    Dio dio,
    String path, {
    required Map<String, Object?> queryParameters,
  }) async {
    try {
      final response = await dio.get<Object?>(
        path,
        queryParameters: queryParameters,
        options: Options(validateStatus: (_) => true),
      );
      final data = response.data;
      if (data is! Map) {
        throw const BaiduNetdiskFileException(
          kind: BaiduNetdiskFileErrorKind.unknown,
          message: 'Baidu response is not a JSON object.',
        );
      }
      _throwIfBaiduError(data);
      return data;
    } on DioException catch (error) {
      throw _mapDioException(error, fallbackMessage: 'Baidu request failed.');
    }
  }

  void _throwIfBaiduError(Map<dynamic, dynamic> data) {
    final errno = _errnoOf(data['errno']);
    if (errno == null || errno == 0) return;
    final message =
        data['errmsg'] as String? ??
        data['error_msg'] as String? ??
        data['error_description'] as String? ??
        'Baidu request failed.';
    throw BaiduNetdiskFileException(
      kind: _kindForErrno(errno),
      message: message,
      errno: errno,
    );
  }

  BaiduNetdiskFileException _mapDioException(
    DioException error, {
    required String fallbackMessage,
  }) {
    if (CancelToken.isCancel(error)) {
      return const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.canceled,
        message: 'Baidu request canceled.',
      );
    }
    final statusCode = error.response?.statusCode;
    final kind = switch (statusCode) {
      401 || 403 => BaiduNetdiskFileErrorKind.unauthorized,
      404 => BaiduNetdiskFileErrorKind.notFound,
      429 => BaiduNetdiskFileErrorKind.rateLimited,
      _ => BaiduNetdiskFileErrorKind.network,
    };
    return BaiduNetdiskFileException(
      kind: kind,
      message: _displayMessageForDioException(
        error,
        fallbackMessage: fallbackMessage,
      ),
      cause: error,
    );
  }

  /// 把 [ReliableHttpDownloader] 的结构化异常映射回既有错误分类。
  ///
  /// httpStatus 按 statusCode 复用与 [_mapDioException] 相同的
  /// unauthorized/notFound/rateLimited 判定；cancelled 映射为 canceled；
  /// 其余 kind（network/timeout/redirect/storage/integrity/conflict/unknown）
  /// 统一归为 network，与迁移前「非 DioException 一律 network」的行为一致。
  BaiduNetdiskFileException _mapReliableDownloadException(
    ReliableDownloadException error, {
    required String fallbackMessage,
  }) {
    if (error.kind == ReliableDownloadFailure.cancelled) {
      return const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.canceled,
        message: 'Baidu request canceled.',
      );
    }
    final kind = switch (error.kind == ReliableDownloadFailure.httpStatus
        ? error.statusCode
        : null) {
      401 || 403 => BaiduNetdiskFileErrorKind.unauthorized,
      404 => BaiduNetdiskFileErrorKind.notFound,
      429 => BaiduNetdiskFileErrorKind.rateLimited,
      _ => BaiduNetdiskFileErrorKind.network,
    };
    return BaiduNetdiskFileException(
      kind: kind,
      message: _displayMessageForReliableDownloadException(
        error,
        fallbackMessage: fallbackMessage,
      ),
      cause: error,
    );
  }

  /// 保留 Dio 底层异常原因，供批量导入结果页展示可排查的失败信息。
  String _displayMessageForDioException(
    DioException error, {
    required String fallbackMessage,
  }) {
    final responseMessage = error.response?.statusMessage;
    final detail = _cleanDioMessage(
      responseMessage,
      error.message,
      error.error?.toString(),
    );
    if (detail == null || detail == fallbackMessage) return fallbackMessage;
    return '$fallbackMessage $detail';
  }

  String? _cleanDioMessage(String? first, String? second, String? third) {
    for (final message in [first, second, third]) {
      if (message == null) continue;
      final trimmed = message.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String _displayMessageForReliableDownloadException(
    ReliableDownloadException error, {
    required String fallbackMessage,
  }) {
    final detail = error.message.trim();
    if (detail.isEmpty || detail == fallbackMessage) return fallbackMessage;
    return '$fallbackMessage $detail';
  }

  int? _errnoOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  BaiduNetdiskFileErrorKind _kindForErrno(int errno) {
    return switch (errno) {
      -6 || 111 || 110 => BaiduNetdiskFileErrorKind.unauthorized,
      -9 || 31066 => BaiduNetdiskFileErrorKind.notFound,
      31045 || 31046 || 31061 => BaiduNetdiskFileErrorKind.rateLimited,
      2 || 31023 => BaiduNetdiskFileErrorKind.badRequest,
      _ => BaiduNetdiskFileErrorKind.unknown,
    };
  }
}

const _baiduUserAgent = 'pan.baidu.com';
