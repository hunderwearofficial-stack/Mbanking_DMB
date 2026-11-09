import 'dart:developer';
import 'package:dio/dio.dart';
import '../constants/api_endpoints.dart';
import '../security/secure_storage_service.dart';
import 'api_exception.dart';

class ApiClient {
  late final Dio dio;
  final SecureStorageService secureStorage;
  Function()? onUnauthorized;

  ApiClient({required this.secureStorage, this.onUnauthorized}) {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. Inject Device ID Header (Device Binding Requirement)
          final deviceID = await secureStorage.getDeviceID();
          options.headers['X-Device-ID'] = deviceID;

          // 2. Inject Bearer JWT Token if available
          final token = await secureStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          log('[DIO REQUEST] ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          log('[DIO RESPONSE] ${response.statusCode} ${response.requestOptions.uri}');
          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          log('[DIO ERROR] ${error.response?.statusCode} ${error.requestOptions.uri}: ${error.message}');

          // Handle 401 Unauthorized (Expired Access Token or Device Mismatch)
          if (error.response?.statusCode == 401) {
            final reqPath = error.requestOptions.path;
            final isAuthEndpoint = reqPath.contains(ApiEndpoints.login) ||
                reqPath.contains(ApiEndpoints.refresh);

            // Attempt automatic background token rotation using RefreshToken
            if (!isAuthEndpoint && error.requestOptions.extra['retried'] != true) {
              final refreshToken = await secureStorage.getRefreshToken();
              if (refreshToken != null && refreshToken.isNotEmpty) {
                try {
                  final deviceID = await secureStorage.getDeviceID();
                  final refreshDio = Dio(
                    BaseOptions(
                      baseUrl: dio.options.baseUrl,
                      connectTimeout: const Duration(seconds: 10),
                      receiveTimeout: const Duration(seconds: 10),
                      headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-Device-ID': deviceID,
                      },
                    ),
                  );
                  final refreshRes = await refreshDio.post(
                    ApiEndpoints.refresh,
                    data: {
                      'refresh_token': refreshToken,
                      'device_id': deviceID,
                    },
                  );
                  final body = refreshRes.data;
                  if (body is Map<String, dynamic> &&
                      body['success'] == true &&
                      body['data'] is Map<String, dynamic>) {
                    final authData = body['data'] as Map<String, dynamic>;
                    final newAccess = (authData['access_token'] ?? '').toString();
                    final newRefresh = (authData['refresh_token'] ?? '').toString();
                    final userMap = authData['user'] is Map<String, dynamic>
                        ? authData['user'] as Map<String, dynamic>
                        : <String, dynamic>{};

                    if (newAccess.isNotEmpty) {
                      await secureStorage.saveAuthData(
                        accessToken: newAccess,
                        refreshToken: newRefresh.isNotEmpty ? newRefresh : refreshToken,
                        phoneNumber: (userMap['phone_number'] ?? await secureStorage.getPhoneNumber() ?? '').toString(),
                        cif: (userMap['cif'] ?? await secureStorage.getCIF() ?? '').toString(),
                        fullName: (userMap['full_name'] ?? await secureStorage.getFullName() ?? '').toString(),
                        primaryAccount: (userMap['primary_account'] ?? await secureStorage.getPrimaryAccount() ?? '').toString(),
                      );

                      // Retry original failed request with the fresh JWT token
                      final opts = error.requestOptions;
                      opts.extra['retried'] = true;
                      opts.headers['Authorization'] = 'Bearer $newAccess';
                      opts.headers['X-Device-ID'] = deviceID;
                      final clonedResponse = await dio.fetch(opts);
                      return handler.resolve(clonedResponse);
                    }
                  }
                } catch (_) {
                  // Refresh token also expired or device unbound -> proceed to clear session & redirect to Login
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
              if (onUnauthorized != null) {
                onUnauthorized!();
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

  // Generic Request Helper with standard banking envelope unwrapping
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await dio.get(path, queryParameters: queryParameters);
      return _handleResponse(response);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError && dio.options.baseUrl != ApiEndpoints.fallbackUrl) {
        try {
          dio.options.baseUrl = ApiEndpoints.fallbackUrl;
          final retryRes = await dio.get(path, queryParameters: queryParameters);
          return _handleResponse(retryRes);
        } catch (_) {
          dio.options.baseUrl = ApiEndpoints.baseUrl;
        }
      }
      throw _handleDioError(e);
    }
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    try {
      final response = await dio.post(path, data: data);
      return _handleResponse(response);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError && dio.options.baseUrl != ApiEndpoints.fallbackUrl) {
        try {
          dio.options.baseUrl = ApiEndpoints.fallbackUrl;
          final retryRes = await dio.post(path, data: data);
          return _handleResponse(retryRes);
        } catch (_) {
          dio.options.baseUrl = ApiEndpoints.baseUrl;
        }
      }
      throw _handleDioError(e);
    }
  }

  dynamic _handleResponse(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      // Standard BPR Banking response: { "success": true, "response_code": "00", "data": ... }
      if (data['success'] == true) {
        return data['data'];
      } else {
        throw ApiException(
          message: data['message'] ?? 'Terjadi kesalahan pada transaksi',
          statusCode: response.statusCode,
          responseCode: data['response_code'],
          errors: data['errors'],
        );
      }
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
      case DioExceptionType.receiveTimeout:
        return ApiException(message: 'Koneksi ke server timeout. Periksa internet Anda.');
      case DioExceptionType.connectionError:
        return ApiException(message: 'Tidak dapat terhubung ke server backend BPR.');
      default:
        return ApiException(message: e.message ?? 'Terjadi kesalahan sistem.');
    }
  }
}

