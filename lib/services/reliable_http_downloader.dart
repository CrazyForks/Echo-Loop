/// 通用可靠 HTTP 下载器。
///
/// 只封装 GET 下载的可靠落盘能力：`.part` 临时文件、可选 Range 续传、
/// 原子 rename 和大小校验。调用方负责拼好最终 URI、headers 与业务错误映射。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:universal_io/io.dart';

/// 可靠下载完成结果。
class ReliableDownloadResult {
  /// 构造下载结果。
  const ReliableDownloadResult({
    required this.savePath,
    required this.bytesWritten,
    required this.resumed,
  });

  /// 最终文件路径。
  final String savePath;

  /// 最终落盘字节数。
  final int bytesWritten;

  /// 本次是否使用了 HTTP Range 追加续传。
  final bool resumed;
}

/// 可靠下载失败。
class ReliableDownloadException implements Exception {
  /// 构造可靠下载失败。
  const ReliableDownloadException(this.message, {this.cause});

  /// 可读错误消息。
  final String message;

  /// 原始异常。
  final Object? cause;

  @override
  String toString() => 'ReliableDownloadException($message)';
}

/// GET 下载器抽象。
abstract interface class ReliableHttpDownloader {
  /// 下载 [uri] 到 [savePath]。
  Future<ReliableDownloadResult> download({
    required Uri uri,
    required String savePath,
    Map<String, String> headers = const <String, String>{},
    int? expectedSize,
    String? identityKey,
    bool allowResume = true,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  });
}

/// 基于 Dio stream 的默认可靠下载器。
class DioReliableHttpDownloader implements ReliableHttpDownloader {
  /// 构造默认实现。
  DioReliableHttpDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<ReliableDownloadResult> download({
    required Uri uri,
    required String savePath,
    Map<String, String> headers = const <String, String>{},
    int? expectedSize,
    String? identityKey,
    bool allowResume = true,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final targetFile = File(savePath);
    final partFile = File('$savePath.part');
    final metaFile = File('$savePath.part.meta.json');
    await targetFile.parent.create(recursive: true);

    final resumableBytes = await _resumableBytes(
      partFile: partFile,
      metaFile: metaFile,
      identityKey: identityKey,
      allowResume: allowResume,
    );
    var shouldResume = resumableBytes > 0;

    for (var attempt = 0; attempt < 2; attempt++) {
      final requestHeaders = <String, String>{...headers};
      if (shouldResume) {
        requestHeaders['Range'] = 'bytes=$resumableBytes-';
      }

      final response = await _getFollowingRedirects(
        uri: uri,
        headers: requestHeaders,
        cancelToken: cancelToken,
      );
      final statusCode = response.statusCode ?? 0;
      final body = response.data;
      if (body == null) {
        throw const ReliableDownloadException(
          'Download response body is empty.',
        );
      }

      if (statusCode == 416) {
        final existingLength = await _lengthIfExists(partFile);
        if (expectedSize != null && existingLength == expectedSize) {
          await _writeMeta(
            metaFile: metaFile,
            identityKey: identityKey,
            expectedSize: expectedSize,
            downloadedBytes: existingLength,
          );
          await _replaceWithPart(partFile: partFile, targetFile: targetFile);
          await _deleteIfExists(metaFile);
          onProgress?.call(existingLength, expectedSize);
          return ReliableDownloadResult(
            savePath: savePath,
            bytesWritten: existingLength,
            resumed: true,
          );
        }
        await _deleteIfExists(partFile);
        await _deleteIfExists(metaFile);
        shouldResume = false;
        continue;
      }

      if (statusCode < 200 || statusCode >= 300) {
        throw DioException.badResponse(
          statusCode: statusCode,
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final append = shouldResume && statusCode == 206;
      if (shouldResume && statusCode == 206) {
        _validateContentRange(
          response.headers.value('content-range'),
          expectedStart: resumableBytes,
        );
      }
      if (shouldResume && statusCode == 200) {
        await _deleteIfExists(partFile);
        await _deleteIfExists(metaFile);
      }

      final initialBytes = append ? resumableBytes : 0;
      final totalBytes = _totalBytesFor(
        response: response,
        initialBytes: initialBytes,
        expectedSize: expectedSize,
      );
      final bytesWritten = await _writeBody(
        body: body,
        partFile: partFile,
        append: append,
        initialBytes: initialBytes,
        totalBytes: totalBytes,
        onProgress: onProgress,
        metaFile: metaFile,
        identityKey: identityKey,
        expectedSize: expectedSize,
      );
      if (expectedSize != null && bytesWritten != expectedSize) {
        throw ReliableDownloadException(
          'Downloaded size mismatch: expected $expectedSize bytes, got $bytesWritten bytes.',
        );
      }
      await _replaceWithPart(partFile: partFile, targetFile: targetFile);
      await _deleteIfExists(metaFile);
      return ReliableDownloadResult(
        savePath: savePath,
        bytesWritten: bytesWritten,
        resumed: append,
      );
    }

    throw const ReliableDownloadException('Download range is not satisfiable.');
  }

  /// 手动跟随 3xx，确保跨域跳转后仍保留调用方注入的下载头。
  ///
  /// 百度网盘 dlink 会先跳到 `*.baidupcs.com`，目标 URL 校验
  /// `User-Agent`。Dio 自动 redirect 在跨域时不会稳定保留这些头，导致
  /// 目标地址返回 31362 sign error，因此这里显式逐跳 GET。
  Future<Response<ResponseBody>> _getFollowingRedirects({
    required Uri uri,
    required Map<String, String> headers,
    required CancelToken? cancelToken,
  }) async {
    var currentUri = uri;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final response = await _dio.get<ResponseBody>(
        currentUri.toString(),
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      );
      final statusCode = response.statusCode ?? 0;
      if (!_isRedirect(statusCode)) return response;

      final location = response.headers.value('location');
      if (location == null || location.isEmpty) {
        throw ReliableDownloadException(
          'Download redirect $statusCode is missing Location.',
        );
      }
      currentUri = currentUri.resolve(location);
    }

    throw const ReliableDownloadException(
      'Download redirected too many times.',
    );
  }

  bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  Future<int> _resumableBytes({
    required File partFile,
    required File metaFile,
    required String? identityKey,
    required bool allowResume,
  }) async {
    if (!allowResume || !await partFile.exists()) return 0;
    final length = await partFile.length();
    if (length <= 0) return 0;
    if (identityKey == null || identityKey.isEmpty) return length;
    final meta = await _readMeta(metaFile);
    if (meta?['identityKey'] == identityKey) return length;
    await _deleteIfExists(partFile);
    await _deleteIfExists(metaFile);
    return 0;
  }

  Future<Map<String, Object?>?> _readMeta(File metaFile) async {
    if (!await metaFile.exists()) return null;
    try {
      final decoded = jsonDecode(await metaFile.readAsString());
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> _writeMeta({
    required File metaFile,
    required String? identityKey,
    required int? expectedSize,
    required int downloadedBytes,
  }) async {
    final data = <String, Object?>{
      'identityKey': identityKey,
      'expectedSize': expectedSize,
      'downloadedBytes': downloadedBytes,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await metaFile.writeAsString(jsonEncode(data));
  }

  void _validateContentRange(String? value, {required int expectedStart}) {
    if (value == null || value.isEmpty) {
      throw const ReliableDownloadException(
        'Partial download response is missing Content-Range.',
      );
    }
    final match = RegExp(r'^bytes\s+(\d+)-\d+/(\d+|\*)$').firstMatch(value);
    final start = match == null ? null : int.tryParse(match.group(1) ?? '');
    if (start != expectedStart) {
      throw ReliableDownloadException(
        'Partial download response starts at ${start ?? 'unknown'}, expected $expectedStart.',
      );
    }
  }

  int? _totalBytesFor({
    required Response<ResponseBody> response,
    required int initialBytes,
    required int? expectedSize,
  }) {
    if (expectedSize != null && expectedSize > 0) return expectedSize;
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      final match = RegExp(r'^bytes\s+\d+-\d+/(\d+)$').firstMatch(contentRange);
      final total = match == null ? null : int.tryParse(match.group(1) ?? '');
      if (total != null && total > 0) return total;
    }
    final contentLength = response.headers.value('content-length');
    final length = contentLength == null ? null : int.tryParse(contentLength);
    if (length == null || length <= 0) return null;
    return initialBytes + length;
  }

  Future<int> _writeBody({
    required ResponseBody body,
    required File partFile,
    required bool append,
    required int initialBytes,
    required int? totalBytes,
    required void Function(int receivedBytes, int? totalBytes)? onProgress,
    required File metaFile,
    required String? identityKey,
    required int? expectedSize,
  }) async {
    var received = initialBytes;
    IOSink? sink;
    try {
      sink = partFile.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      await for (final chunk in body.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, totalBytes);
        await _writeMeta(
          metaFile: metaFile,
          identityKey: identityKey,
          expectedSize: expectedSize,
          downloadedBytes: received,
        );
      }
      await sink.flush();
      await sink.close();
      return received;
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {}
      if (error is DioException && CancelToken.isCancel(error)) rethrow;
      throw ReliableDownloadException(
        'Failed to save download stream.',
        cause: error,
      );
    }
  }

  Future<void> _replaceWithPart({
    required File partFile,
    required File targetFile,
  }) async {
    await _deleteIfExists(targetFile);
    await partFile.rename(targetFile.path);
  }

  Future<int> _lengthIfExists(File file) async {
    if (!await file.exists()) return 0;
    return file.length();
  }

  Future<void> _deleteIfExists(File file) async {
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {}
  }
}
