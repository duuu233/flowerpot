import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException, IOException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';
import 'api_session.dart';

typedef SessionExpiredCallback = void Function();

/// Shared JSON/multipart client for the app's REST services.
///
/// It reuses one HTTP connection pool, injects common request parameters,
/// retries transport failures only, parses the `retCode/retMsg/retData`
/// envelope, and redacts credentials from debug logs.
class ApiClient {
  ApiClient({
    required String baseUrl,
    ApiSession? session,
    http.Client? httpClient,
    this.timeout = ApiConfig.timeout,
    this.uploadTimeout = ApiConfig.uploadTimeout,
    this.networkRetryMax = ApiConfig.networkRetryMax,
    this.networkRetryDelay = ApiConfig.networkRetryDelay,
    this.clientPathPrefix = '/Client/',
    this.onSessionExpired,
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       session = session ?? ApiSession.instance,
       _http = httpClient ?? http.Client(),
       _ownsClient = httpClient == null {
    if (this.baseUrl.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must not be empty');
    }
  }

  factory ApiClient.fromEnvironment({
    ApiSession? session,
    SessionExpiredCallback? onSessionExpired,
  }) => ApiClient(
    baseUrl: ApiConfig.baseUrl,
    session: session,
    onSessionExpired: onSessionExpired,
  );

  final String baseUrl;
  final ApiSession session;
  final Duration timeout;
  final Duration uploadTimeout;
  final int networkRetryMax;
  final Duration networkRetryDelay;
  final String clientPathPrefix;
  final SessionExpiredCallback? onSessionExpired;
  final http.Client _http;
  final bool _ownsClient;

  http.Client get httpClient => _http;

  Future<Object?> getJson(
    String path, {
    Map<String, Object?>? query,
    bool auth = true,
  }) {
    final uri = _uri(path, <String, Object?>{
      ..._clientQuery(path, auth: auth),
      ...?query,
    });
    _logRequest('GET', uri, query);
    return _sendWithRetry(
      'GET',
      uri,
      () => _http.get(uri, headers: _headers(auth: auth)).timeout(timeout),
    );
  }

  Future<Object?> postJson(
    String path, {
    Map<String, Object?>? body,
    bool auth = true,
    bool retryOnTimeout = true,
  }) {
    final uri = _uri(path, _clientQuery(path, auth: auth));
    final payload = body ?? const <String, Object?>{};
    _logRequest('POST', uri, payload);
    return _sendWithRetry(
      'POST',
      uri,
      () => _http
          .post(
            uri,
            headers: _headers(
              auth: auth,
              extra: const <String, String>{'content-type': 'application/json'},
            ),
            body: jsonEncode(payload),
          )
          .timeout(timeout),
      retryOnTimeout: retryOnTimeout,
    );
  }

  Future<Object?> upload(
    String path, {
    required List<String> filePaths,
    String field = 'fileParam',
    Map<String, Object?>? query,
    Map<String, Object?>? formData,
    bool auth = true,
  }) async {
    if (filePaths.isEmpty) {
      throw const ApiException('UPLOAD_FILE_REQUIRED', '请选择需要上传的文件');
    }
    final results = <Object?>[];
    for (final filePath in filePaths) {
      final uri = _uri(path, <String, Object?>{
        ..._clientQuery(path, auth: auth),
        ...?query,
      });
      _logRequest('POST multipart', uri, <String, Object?>{
        ...?formData,
        'fileName': filePath.split(RegExp(r'[/\\]')).last,
      });
      try {
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers(auth: auth));
        formData?.forEach((key, value) {
          if (value != null) request.fields[key] = value.toString();
        });
        request.files.add(await http.MultipartFile.fromPath(field, filePath));
        final streamed = await _http.send(request).timeout(uploadTimeout);
        final response = await http.Response.fromStream(
          streamed,
        ).timeout(uploadTimeout);
        _logResponse('POST multipart', uri, response);
        results.add(_parse(response));
      } on ApiException {
        rethrow;
      } on TimeoutException {
        throw const ApiException('NETWORK_TIMEOUT', '网络请求超时，请稍后重试');
      } on FileSystemException {
        throw const ApiException('UPLOAD_FILE_MISSING', '文件不存在或已被清理，请重新选择');
      } on Exception {
        throw const ApiException('NETWORK_UNREACHABLE', '网络连接失败，请稍后重试');
      }
    }
    return results.length == 1 ? results.first : results;
  }

  void close() {
    if (_ownsClient) _http.close();
  }

  Map<String, String> _headers({
    required bool auth,
    Map<String, String>? extra,
  }) {
    final headers = <String, String>{
      'terminal': ApiConfig.terminal.toString(),
      'language': session.languageCode.toString(),
    };
    if (auth && session.userToken.isNotEmpty) {
      headers['userToken'] = session.userToken;
      headers['Authorization'] = 'Bearer ${session.userToken}';
    }
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  Map<String, Object?> _clientQuery(String path, {required bool auth}) {
    if (!path.startsWith(clientPathPrefix)) return const <String, Object?>{};
    return <String, Object?>{
      'terminal': ApiConfig.terminal,
      'language': session.languageCode,
      if (auth && session.userToken.isNotEmpty) 'userToken': session.userToken,
    };
  }

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');
    if (query == null || query.isEmpty) return uri;
    final merged = <String, String>{...uri.queryParameters};
    query.forEach((key, value) {
      final text = value?.toString() ?? '';
      if (text.isNotEmpty) merged[key] = text;
    });
    return uri.replace(queryParameters: merged);
  }

  Future<Object?> _sendWithRetry(
    String method,
    Uri uri,
    Future<http.Response> Function() send, {
    bool retryOnTimeout = true,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await send();
        _logResponse(method, uri, response);
        return _parse(response);
      } on ApiException {
        rethrow;
      } on TimeoutException {
        if (retryOnTimeout && attempt < networkRetryMax) {
          attempt++;
          await Future<void>.delayed(networkRetryDelay);
          continue;
        }
        throw const ApiException('NETWORK_TIMEOUT', '网络请求超时，请稍后重试');
      } on http.ClientException {
        if (attempt < networkRetryMax) {
          attempt++;
          await Future<void>.delayed(networkRetryDelay);
          continue;
        }
        throw const ApiException('NETWORK_UNREACHABLE', '网络连接失败，请稍后重试');
      } on IOException {
        if (attempt < networkRetryMax) {
          attempt++;
          await Future<void>.delayed(networkRetryDelay);
          continue;
        }
        throw const ApiException('NETWORK_UNREACHABLE', '网络连接失败，请稍后重试');
      } on Exception {
        throw const ApiException('CLIENT_ERROR', '请求处理失败，请稍后重试');
      }
    }
  }

  Object? _parse(http.Response response) {
    Map<String, Object?> body = const <String, Object?>{};
    var parseFailed = false;
    try {
      final text = utf8.decode(response.bodyBytes);
      final decoded = text.isEmpty ? null : jsonDecode(text);
      if (decoded is Map) {
        body = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      parseFailed = response.bodyBytes.isNotEmpty;
    }

    final retCode = body['retCode'];
    final retMessage = body['retMsg']?.toString();
    if (response.statusCode == 401 || retCode == 401 || retCode == 406) {
      session.clear();
      onSessionExpired?.call();
      throw ApiException(retCode ?? 401, retMessage ?? '登录状态已失效，请重新登录');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        retMessage ?? '服务器暂时不可用，请稍后重试',
        authError: false,
      );
    }
    if (parseFailed) {
      throw const ApiException('PARSE_ERROR', '服务器返回的数据格式不正确');
    }
    if (body.containsKey('retCode')) {
      if (retCode != 200) {
        throw ApiException(
          retCode ?? -1,
          retMessage ?? '请求失败，请稍后重试',
          data: body['retData'],
        );
      }
      return body['retData'];
    }
    return body;
  }

  void _logRequest(String method, Uri uri, Object? data) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] --> $method ${_redactUri(uri)}');
    if (data != null) {
      debugPrint('[HTTP] request: ${jsonEncode(_redact(data))}');
    }
  }

  void _logResponse(String method, Uri uri, http.Response response) {
    if (!kDebugMode) return;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    debugPrint('[HTTP] <-- ${response.statusCode} $method ${_redactUri(uri)}');
    debugPrint('[HTTP] response: ${jsonEncode(_redactJson(text))}');
  }

  Uri _redactUri(Uri uri) {
    if (!uri.queryParameters.containsKey('userToken')) return uri;
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'userToken': '***',
      },
    );
  }

  Object? _redactJson(String text) {
    try {
      return _redact(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  Object? _redact(Object? value, [String? key]) {
    const sensitiveKeys = <String>{
      'authorization',
      'password',
      'confirmpassword',
      'token',
      'usertoken',
      'credential',
      'code',
    };
    if (key != null && sensitiveKeys.contains(key.toLowerCase())) return '***';
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _redact(item, key.toString())),
      );
    }
    if (value is Iterable) return value.map((item) => _redact(item)).toList();
    return value;
  }
}
