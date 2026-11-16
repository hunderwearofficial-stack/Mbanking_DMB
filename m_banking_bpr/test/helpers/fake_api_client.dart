import 'package:m_banking_bpr/core/network/api_client.dart';
import 'package:m_banking_bpr/core/network/api_exception.dart';
import 'package:m_banking_bpr/core/security/secure_storage_service.dart';

/// Test double: simulates the backend reporting a Core Banking outage (HTTP 503).
class FailingApiClient extends ApiClient {
  FailingApiClient() : super(secureStorage: SecureStorageService());

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async =>
      throw ApiException(message: 'Data belum dapat ditampilkan. Silakan coba kembali.', statusCode: 503);
}

/// Test double with scripted responses; records the last POST.
class ScriptedApiClient extends ApiClient {
  dynamic getResult;
  dynamic postResult;
  ApiException? postError;
  Map<String, dynamic>? lastHeaders;
  Map<String, dynamic>? lastBody;
  int postCount = 0;

  ScriptedApiClient({this.getResult, this.postResult, this.postError}) : super(secureStorage: SecureStorageService());

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async => getResult;

  @override
  Future<dynamic> post(String path, {dynamic data, Map<String, dynamic>? headers, Duration? receiveTimeout}) async {
    postCount++;
    lastHeaders = headers;
    lastBody = data is Map<String, dynamic> ? data : null;
    if (postError != null) throw postError!;
    return postResult;
  }
}
