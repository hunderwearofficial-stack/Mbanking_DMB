import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/security/secure_storage_service.dart';
import '../models/user_model.dart';

class AuthRepository {
  final ApiClient apiClient;
  final SecureStorageService secureStorage;

  AuthRepository({required this.apiClient, required this.secureStorage});

  Future<AuthResponseModel> login({
    required String identifier,
    required String password,
    String? deviceId,
  }) async {
    final devId = deviceId ?? await secureStorage.getDeviceID();

    final response = await apiClient.post(
      ApiEndpoints.login,
      data: {
        'phone_number': identifier,
        'password': password,
        'device_id': devId,
      },
    );

    final authResponse = AuthResponseModel.fromJson(response);

    // Save tokens and user data securely
    await secureStorage.saveAuthData(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
      phoneNumber: authResponse.user.phoneNumber,
      cif: authResponse.user.cif,
      fullName: authResponse.user.fullName,
      primaryAccount: authResponse.user.primaryAccount,
    );

    if (authResponse.user.deviceId.isNotEmpty) {
      await secureStorage.setDeviceID(authResponse.user.deviceId);
    }

    return authResponse;
  }

  Future<void> logout() async {
    await secureStorage.clearAuthData();
  }

  Future<bool> isLoggedIn() async {
    return await secureStorage.hasValidToken();
  }

  // ==================== SELF-ACTIVATION FLOW ====================

  Future<Map<String, dynamic>> verifyActivationAccount({
    required String accountNumber,
    required String phoneNumber,
  }) async {
    final devId = await secureStorage.getDeviceID();
    final response = await apiClient.post(
      ApiEndpoints.activateVerify,
      data: {
        'account_number': accountNumber,
        'phone_number': phoneNumber,
        'device_id': devId,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{};
  }

  Future<bool> verifyActivationOtp({
    required String sessionId,
    required String otpCode,
  }) async {
    await apiClient.post(
      ApiEndpoints.activateOtp,
      data: {
        'session_id': sessionId,
        'otp_code': otpCode,
      },
    );
    return true;
  }

  Future<AuthResponseModel> completeActivation({
    required String sessionId,
    required String password,
    required String pin,
  }) async {
    final devId = await secureStorage.getDeviceID();
    final response = await apiClient.post(
      ApiEndpoints.activateSetup,
      data: {
        'session_id': sessionId,
        'password': password,
        'pin': pin,
        'device_id': devId,
      },
    );

    final authResponse = AuthResponseModel.fromJson(response);

    await secureStorage.saveAuthData(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
      phoneNumber: authResponse.user.phoneNumber,
      cif: authResponse.user.cif,
      fullName: authResponse.user.fullName,
      primaryAccount: authResponse.user.primaryAccount,
    );

    if (authResponse.user.deviceId.isNotEmpty) {
      await secureStorage.setDeviceID(authResponse.user.deviceId);
    }

    return authResponse;
  }
}

