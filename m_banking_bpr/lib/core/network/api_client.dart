import 'dart:async';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import '../constants/api_endpoints.dart';
import '../security/device_binding_service.dart';
import '../security/device_identity_service.dart';
import '../security/secure_storage_service.dart';
import '../security/ssl_pinning_service.dart';
import '../services/dynamic_config_service.dart';
import 'api_exception.dart';

class ApiClient {
  late final Dio dio;
  final SecureStorageService secureStorage;
  final DeviceBindingService deviceBinding;
  Function()? onUnauthorized;

  static Completer<String?>? _refreshInFlight;

  static const String insideAuthLockKey = 'insideAuthLock';
  static const String _sentTokenKey = 'sentAccessToken';

  ApiClient({required this.secureStorage, this.onUnauthorized, DeviceBindingService? deviceBinding})
      : deviceBinding = deviceBinding ?? DeviceBindingService(storage: secureStorage, isIOS: () => Platform.isIOS) {
    dio = createSecureDio(baseUrl: ApiEndpoints.baseUrl);
    _setupInterceptors();
  }

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
          final isLocalOrDev = AppEnvironment.flavor == AppFlavor.local || AppEnvironment.flavor == AppFlavor.development;
          if (kReleaseMode && !isLocalOrDev && options.uri.scheme.toLowerCase() != 'https') {
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

  Future<String?> _currentAccessToken() async {
    try {
      return await secureStorage.getAccessToken();
    } on DeviceSecurityException {
      return null;
    }
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            if (options.extra[insideAuthLockKey] != true) {
              await AuthSessionLock.instance.idle;
            }
            final preAuth = ApiEndpoints.isPreAuth(options.path);
            final token = preAuth ? null : await secureStorage.getAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
              options.extra[_sentTokenKey] = token;
            }
            if (options.headers['X-Device-ID'] == null) {
              final fromToken = DeviceBindingService.deviceIdFromToken(token);
              options.headers['X-Device-ID'] = fromToken ?? await secureStorage.getDeviceID();
            }
          } on DeviceSecurityException catch (e) {
            return handler.reject(DioException(
              requestOptions: options,
              error: ApiException(message: e.userMessage, responseCode: e.code, kind: ApiFailureKind.notSent),
            ));
          }
          if (kDebugMode) {
            log('[DIO REQUEST] ${options.method} ${options.path}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          DynamicConfigService().setServerConnected(true);
          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          final statusCode = error.response?.statusCode;
          if (error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              statusCode == 502 ||
              statusCode == 503 ||
              statusCode == 504) {
            DynamicConfigService().setServerConnected(false);
          } else if (statusCode != null && statusCode < 500) {
            DynamicConfigService().setServerConnected(true);
          }

          if (statusCode == 401) {
            final opts = error.requestOptions;
            final reqPath = opts.path;
            final isAuthEndpoint =
                ApiEndpoints.isPreAuth(reqPath) || reqPath.contains(ApiEndpoints.refresh) || reqPath.contains(ApiEndpoints.logout);
            final sent = opts.extra[_sentTokenKey] as String?;

            // SR-1: a request issued inside an AuthSessionLock operation (login, refresh,
            // activation, enrollment) must never refresh, retry or clear the session here:
            // the refresh would wait for the lock held by that very operation (deadlock).
            // The 401 is returned to the operation, which keeps or ends the session itself.
            if (opts.extra[insideAuthLockKey] == true) {
              final data = error.response?.data;
              return handler.reject(DioException(
                requestOptions: opts,
                response: error.response,
                error: ApiException(
                  message: data is Map && data['message'] != null
                      ? ApiException.sanitizeText(data['message'].toString(), fallback: 'Sesi tidak valid.')
                      : 'Sesi tidak valid.',
                  statusCode: 401,
                  responseCode: data is Map ? data['response_code']?.toString() : '01',
                ),
              ));
            }

            final current = await _currentAccessToken();
            if (!isAuthEndpoint &&
                sent != null &&
                current != null &&
                current.isNotEmpty &&
                current != sent &&
                opts.extra['retried'] != true) {
              try {
                opts.extra['retried'] = true;
                opts.headers.remove('Authorization');
                opts.headers.remove('X-Device-ID');
                return handler.resolve(await dio.fetch(opts));
              } on DioException catch (e) {
                return handler.next(e);
              }
            }

            if (!isAuthEndpoint && opts.extra['retried'] != true) {
              final newAccess = await _refreshAccessToken();
              if (newAccess != null) {
                try {
                  opts.extra['retried'] = true;
                  opts.headers.remove('Authorization');
                  opts.headers.remove('X-Device-ID');
                  final cloned = await dio.fetch(opts);
                  return handler.resolve(cloned);
                } catch (_) {
                }
              }
            }

            final data = error.response?.data;
            String message = 'Sesi Anda telah berakhir, silakan login kembali.';
            if (data is Map && data['message'] != null) {
              message = ApiException.sanitizeText(data['message'].toString(), fallback: message);
            }
            if (!isAuthEndpoint) {
              final now = await _currentAccessToken();
              if (sent == null || now == sent) {
                try {
                  await secureStorage.clearSessionTokens();
                } on DeviceSecurityException {
                }
                onUnauthorized?.call();
              }
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

  Future<String?> _refreshAccessToken() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight.future;
    }
    final completer = Completer<String?>();
    _refreshInFlight = completer;
    try {
      final result = await AuthSessionLock.instance.run(() async {
        final refreshToken = await secureStorage.getRefreshToken();
        final deviceID = DeviceBindingService.deviceIdFromToken(refreshToken);
        if (refreshToken == null || refreshToken.isEmpty || deviceID == null) {
          return null;
        }
        final refreshDio = createSecureDio(
          baseUrl: dio.options.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'X-Device-ID': deviceID},
        );
        refreshDio.httpClientAdapter = dio.httpClientAdapter;
        Future<dynamic> post(String path, Map<String, dynamic> body) async {
          final res = await refreshDio.post(path, data: body);
          final b = res.data;
          if (b is Map<String, dynamic> && b['success'] == true) return b['data'];
          throw ApiException(message: 'Permintaan ditolak', statusCode: res.statusCode);
        }

        final payload = <String, dynamic>{'refresh_token': refreshToken, 'device_id': deviceID};
        final proof = await deviceBinding.prove(
          post: post,
          challengePath: ApiEndpoints.deviceChallenge,
          challengeBody: {'refresh_token': refreshToken, 'device_id': deviceID},
          purpose: 'REFRESH',
          deviceId: deviceID,
        );
        if (proof != null) payload.addAll(proof.toJson());
        final authData = await post(ApiEndpoints.refresh, payload);
        if (authData is! Map<String, dynamic>) return null;
        final newAccess = (authData['access_token'] ?? '').toString();
        final newRefresh = (authData['refresh_token'] ?? '').toString();
        final userMap = authData['user'] is Map<String, dynamic> ? authData['user'] as Map<String, dynamic> : <String, dynamic>{};
        if (newAccess.isEmpty || newRefresh.isEmpty) return null;
        await secureStorage.saveAuthData(
          accessToken: newAccess,
          refreshToken: newRefresh,
          phoneNumber: (userMap['phone_number'] ?? await secureStorage.getPhoneNumber() ?? '').toString(),
          cif: (userMap['cif'] ?? await secureStorage.getCIF() ?? '').toString(),
          fullName: (userMap['full_name'] ?? await secureStorage.getFullName() ?? '').toString(),
          primaryAccount: (userMap['primary_account'] ?? await secureStorage.getPrimaryAccount() ?? '').toString(),
        );
        return newAccess;
      });
      completer.complete(result);
    } catch (_) {
      completer.complete(null);
    } finally {
      _refreshInFlight = null;
    }
    return completer.future;
  }

  Future<dynamic> postInsideAuthLock(String path, Map<String, dynamic> data, {Map<String, dynamic>? headers}) =>
      _send(() => dio.post(path, data: data, options: Options(headers: headers, extra: {insideAuthLockKey: true})));

  Future<dynamic> _send(Future<Response> Function() call) async {
    try {
      return _handleResponse(await call());
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _send(() => dio.get(path, queryParameters: queryParameters));

  Future<dynamic> post(String path, {dynamic data, Map<String, dynamic>? headers, Duration? receiveTimeout}) =>
      _send(() => dio.post(path,
          data: data,
          options: (headers == null && receiveTimeout == null) ? null : Options(headers: headers, receiveTimeout: receiveTimeout)));

  Future<dynamic> delete(String path, {Map<String, dynamic>? headers}) =>
      _send(() => dio.delete(path, options: headers == null ? null : Options(headers: headers)));

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
        message: ApiException.sanitizeText(
          (data['message'] ?? 'Permintaan belum dapat diproses. Silakan coba kembali.').toString(),
          fallback: 'Permintaan belum dapat diproses. Silakan coba kembali.',
        ),
        statusCode: response.statusCode,
        responseCode: data['response_code']?.toString(),
        errors: data['errors'],
      );
    }
    return data;
  }

  ApiException _handleDioError(DioException e) {
    if (e.error is ApiException) {
      return e.error as ApiException;
    }
    final statusCode = e.response?.statusCode;
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      final resData = e.response?.data;
      final customMsg = (resData is Map && resData['message'] != null)
          ? ApiException.sanitizeText(
              resData['message'].toString(),
              fallback: 'Layanan sedang tidak tersedia. Silakan coba kembali beberapa saat lagi.',
            )
          : 'Layanan sedang tidak tersedia. Silakan coba kembali beberapa saat lagi.';
      return ApiException(
        message: customMsg,
        statusCode: statusCode,
        responseCode: resData is Map ? resData['response_code']?.toString() : null,
        kind: ApiFailureKind.server,
      );
    }
    if (e.response != null && e.response?.data is Map) {
      final resData = e.response!.data as Map;
      return ApiException(
        message: ApiException.sanitizeText(
          (resData['message'] ?? 'Permintaan belum dapat diproses. Silakan coba kembali.').toString(),
          fallback: 'Permintaan belum dapat diproses. Silakan coba kembali.',
        ),
        statusCode: statusCode,
        responseCode: resData['response_code']?.toString(),
        errors: resData['errors'],
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          message: 'Koneksi membutuhkan waktu lebih lama dari biasanya. Silakan coba kembali.',
          kind: ApiFailureKind.notSent,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          message: 'Koneksi sedang bermasalah. Periksa jaringan internet Anda dan coba kembali.',
          kind: ApiFailureKind.notSent,
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          message: 'Koneksi tidak dapat diverifikasi secara aman. Pastikan aplikasi Anda versi terbaru.',
          kind: ApiFailureKind.notSent,
        );
      case DioExceptionType.cancel:
        return ApiException(message: 'Permintaan dibatalkan.', kind: ApiFailureKind.notSent);
      default:
        return ApiException(
          message: 'Layanan sedang tidak tersedia. Silakan coba kembali beberapa saat lagi.',
          kind: ApiFailureKind.outcomeUnknown,
        );
    }
  }
}
