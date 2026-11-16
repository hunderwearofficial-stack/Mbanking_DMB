import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_endpoints.dart';
import '../security/secure_storage_service.dart';
import '../security/ssl_pinning_service.dart';
import 'api_exception.dart';

class ApiClient {
  late final Dio dio;
  final SecureStorageService secureStorage;
  Function()? onUnauthorized;

  /// Shared in-flight refresh so that parallel 401s trigger only ONE refresh call
  /// (the server rotates refresh tokens and treats reuse as theft — audit DMB-014).
  static Completer<String?>? _refreshInFlight;

  ApiClient({required this.secureStorage, this.onUnauthorized}) {
    dio = createSecureDio(baseUrl: ApiEndpoints.baseUrl);
    _setupInterceptors();
  }

  /// Creates a Dio instance with the banking transport policy (audit DMB-010):
  ///  * normal platform TLS validation is never bypassed;
  ///  * certificate pinning when API_CERT_PINS is configured;
  ///  * release builds refuse any non-HTTPS request.
  static Dio createSecureDio({
    required String baseUrl,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 15),
    Map<String, dynamic>? headers,
  }) {
    final d = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: headers ??
            {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
      ),
    );
    if (d.httpClientAdapter is IOHttpClientAdapter) {
      d.httpClientAdapter = IOHttpClientAdapter(
        validateCertificate: SslPinningService.validateCertificate,
      );
    }
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (kReleaseMode && options.uri.scheme.toLowerCase() != 'https') {
            return handler.reject(
              DioException(
                requestOptions: options,
                error: ApiException(message: 'Koneksi tidak aman ditolak. Hubungi Bank DMB.'),
              ),
            );
          }
          return handler.next(options);
        },
      ),
    );
    return d;
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. Device binding header
          final deviceID = await secureStorage.getDeviceID();
          options.headers['X-Device-ID'] = deviceID;

          // 2. Bearer token
          final token = await secureStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (kDebugMode) {
            log('[DIO REQUEST] ${options.method} ${options.path}');
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            final reqPath = error.requestOptions.path;
            final isAuthEndpoint = reqPath.contains(ApiEndpoints.login) ||
                reqPath.contains(ApiEndpoints.refresh) ||
                reqPath.contains(ApiEndpoints.logout);

            if (!isAuthEndpoint && error.requestOptions.extra['retried'] != true) {
              final newAccess = await _refreshAccessToken();
              if (newAccess != null) {
                try {
                  final opts = error.requestOptions;
                  opts.extra['retried'] = true;
                  opts.headers['Authorization'] = 'Bearer $newAccess';
                  final cloned = await dio.fetch(opts);
                  return handler.resolve(cloned);
                } catch (_) {
                  // fall through to session expiry handling
                }
              }
            }

            final data = error.response?.data;
            String message = 'Sesi Anda telah berakhir, silakan login kembali.';
            if (data is Map && data['message'] != null) {
              message = data['message'].toString();
            }
            if (!isAuthEndpoint) {
              await secureStorage.clearSessionTokens();
              onUnauthorized?.call();
            }
            return handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                error: ApiException(
                  message: message,
                  statusCode: 401,
                  responseCode: data is Map ? data['response_code'] : '01',
                ),
              ),
            );
          }
          return handler.next(error);
        },
      ),
    );
  }

  /// Refreshes the session once, even when called concurrently. Returns the new
  /// access token or null if the session can no longer be refreshed.
  Future<String?> _refreshAccessToken() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight.future;
    }
    final completer = Completer<String?>();
    _refreshInFlight = completer;
    try {
      final refreshToken = await secureStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        completer.complete(null);
        return completer.future;
      }
      final deviceID = await secureStorage.getDeviceID();
      final refreshDio = createSecureDio(
        baseUrl: dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Device-ID': deviceID,
        },
      );
      final res = await refreshDio.post(
        ApiEndpoints.refresh,
        data: {'refresh_token': refreshToken, 'device_id': deviceID},
      );
      final body = res.data;
      if (body is Map<String, dynamic> && body['success'] == true && body['data'] is Map<String, dynamic>) {
        final authData = body['data'] as Map<String, dynamic>;
        final newAccess = (authData['access_token'] ?? '').toString();
        final newRefresh = (authData['refresh_token'] ?? '').toString();
        final userMap = authData['user'] is Map<String, dynamic> ? authData['user'] as Map<String, dynamic> : <String, dynamic>{};
        if (newAccess.isNotEmpty && newRefresh.isNotEmpty) {
          await secureStorage.saveAuthData(
            accessToken: newAccess,
            refreshToken: newRefresh,
            phoneNumber: (userMap['phone_number'] ?? await secureStorage.getPhoneNumber() ?? '').toString(),
            cif: (userMap['cif'] ?? await secureStorage.getCIF() ?? '').toString(),
            fullName: (userMap['full_name'] ?? await secureStorage.getFullName() ?? '').toString(),
            primaryAccount: (userMap['primary_account'] ?? await secureStorage.getPrimaryAccount() ?? '').toString(),
          );
          completer.complete(newAccess);
          return completer.future;
        }
      }
      completer.complete(null);
    } catch (_) {
      completer.complete(null);
    } finally {
      _refreshInFlight = null;
    }
    return completer.future;
  }

  /// Executes a request. There is no fallback server: a failure is reported to the
  /// caller (no silent retry against another backend).
  Future<dynamic> _send(Future<Response> Function() call) async {
    try {
      return _handleResponse(await call());
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _send(() => dio.get(path, queryParameters: queryParameters));

  /// [receiveTimeout] overrides the default for slow operations (e.g. a transfer waits
  /// for Core Banking up to 30 s on the server side).
  Future<dynamic> post(String path, {dynamic data, Map<String, dynamic>? headers, Duration? receiveTimeout}) =>
      _send(() => dio.post(path,
          data: data,
          options: (headers == null && receiveTimeout == null) ? null : Options(headers: headers, receiveTimeout: receiveTimeout)));

  Future<dynamic> delete(String path) => _send(() => dio.delete(path));

  /// Downloads binary content (e.g. a PDF). Failures are classified like other requests.
  Future<Uint8List> getBytes(String path) async {
    try {
      final res = await dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
      final data = res.data;
      if (res.statusCode != 200 || data == null || data.isEmpty) {
        throw ApiException(message: 'Dokumen tidak dapat dimuat. Silakan coba kembali.', statusCode: res.statusCode);
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response != null) {
        throw ApiException(message: 'Dokumen tidak dapat dimuat. Silakan coba kembali.', statusCode: e.response?.statusCode);
      }
      throw _handleDioError(e);
    }
  }

  dynamic _handleResponse(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['success'] == true) {
        return data['data'];
      }
      throw ApiException(
        message: data['message'] ?? 'Terjadi kesalahan pada transaksi',
        statusCode: response.statusCode,
        responseCode: data['response_code'],
        errors: data['errors'],
      );
    }
    return data;
  }

  ApiException _handleDioError(DioException e) {
    if (e.error is ApiException) {
      return e.error as ApiException;
    }
    if (e.response != null && e.response?.data is Map) {
      final resData = e.response!.data as Map;
      return ApiException(
        message: resData['message'] ?? 'Permintaan gagal diproses',
        statusCode: e.response?.statusCode,
        responseCode: resData['response_code'],
        errors: resData['errors'],
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return ApiException(
            message: 'Layanan sedang mengalami gangguan. Silakan coba kembali beberapa saat lagi.', kind: ApiFailureKind.notSent);
      case DioExceptionType.connectionError:
        return ApiException(
            message: 'Tidak dapat terhubung ke server Bank DMB. Periksa koneksi internet Anda lalu coba kembali.',
            kind: ApiFailureKind.notSent);
      case DioExceptionType.badCertificate:
        return ApiException(
            message: 'Sertifikat server tidak valid. Koneksi dihentikan demi keamanan.', kind: ApiFailureKind.notSent);
      case DioExceptionType.cancel:
        return ApiException(message: 'Permintaan dibatalkan.', kind: ApiFailureKind.notSent);
      default:
        // sendTimeout / receiveTimeout / unknown: the request may have reached the server.
        return ApiException(
            message: 'Layanan sedang mengalami gangguan. Silakan coba kembali beberapa saat lagi.',
            kind: ApiFailureKind.outcomeUnknown);
    }
  }
}
