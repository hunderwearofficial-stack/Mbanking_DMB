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
        'cif': identifier,
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

    // If biometric login is enabled, keep biometric credentials up to date
    if (await secureStorage.isBiometricEnabled()) {
      await secureStorage.saveBiometricCredentials(
        refreshToken: authResponse.refreshToken,
        cif: authResponse.user.cif,
        phone: authResponse.user.phoneNumber,
        fullName: authResponse.user.fullName,
        primaryAccount: authResponse.user.primaryAccount,
      );
    }

    if (authResponse.user.deviceId.isNotEmpty &&
        !authResponse.user.deviceId.contains('DEMO')) {
      await secureStorage.setDeviceID(authResponse.user.deviceId);
    }

    return authResponse;
  }

  Future<UserModel> loginWithBiometric() async {
    final isBio = await secureStorage.isBiometricEnabled();
    if (!isBio) {
      throw Exception('Login Biometrik belum diaktifkan.');
    }

    final refreshToken = await secureStorage.getBiometricRefreshToken() ?? await secureStorage.getRefreshToken();
    final cif = await secureStorage.getBiometricCif() ?? await secureStorage.getCIF() ?? '';
    final phone = await secureStorage.getBiometricPhone() ?? await secureStorage.getPhoneNumber() ?? '';
    final fullName = await secureStorage.getBiometricFullName() ?? await secureStorage.getFullName() ?? 'Nasabah Bank DMB';
    final primaryAcc = await secureStorage.getBiometricPrimaryAccount() ?? await secureStorage.getPrimaryAccount() ?? '';
    final devId = await secureStorage.getDeviceID();

    if (cif.isEmpty && phone.isEmpty) {
      throw Exception('Kredensial biometrik belum tersimpan. Silakan login menggunakan password sekali lagi.');
    }

    // 1. Try refreshing session with server using the stored biometric refresh token
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final response = await apiClient.post(
          ApiEndpoints.refresh,
          data: {
            'refresh_token': refreshToken,
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
        await secureStorage.saveBiometricCredentials(
          refreshToken: authResponse.refreshToken,
          cif: authResponse.user.cif,
          phone: authResponse.user.phoneNumber,
          fullName: authResponse.user.fullName,
          primaryAccount: authResponse.user.primaryAccount,
        );
        return authResponse.user;
      } catch (_) {
        // Fall through to offline authorized profile
      }
    }

    // 2. Offline authorized user profile (fingerprint verified by native hardware sensor)
    final user = UserModel(
      id: '',
      cif: cif,
      fullName: fullName,
      phoneNumber: phone,
      email: '',
      deviceId: devId,
      primaryAccount: primaryAcc,
      isActive: true,
    );

    await secureStorage.saveAuthData(
      accessToken: 'bio_session_active',
      refreshToken: refreshToken ?? '',
      phoneNumber: phone,
      cif: cif,
      fullName: fullName,
      primaryAccount: primaryAcc,
    );

    return user;
  }

  Future<void> logout() async {
    await secureStorage.clearAuthData();
  }

  Future<bool> isLoggedIn() async {
    return await secureStorage.hasValidToken();
  }

  Future<AuthResponseModel?> refreshSession() async {
    final refreshToken = await secureStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    final devId = await secureStorage.getDeviceID();
    final response = await apiClient.post(
      ApiEndpoints.refresh,
      data: {
        'refresh_token': refreshToken,
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
    return authResponse;
  }

  // ==================== SELF-ACTIVATION FLOW ====================

  Future<Map<String, dynamic>> verifyActivationAccount({
    String? cifNumber,
    String? accountNumber,
    required String phoneNumber,
  }) async {
    final devId = await secureStorage.getDeviceID();
    final cif = cifNumber ?? accountNumber ?? '';
    final response = await apiClient.post(
      ApiEndpoints.activateVerify,
      data: {
        'cif_number': cif,
        'account_number': cif,
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

    if (authResponse.user.deviceId.isNotEmpty &&
        !authResponse.user.deviceId.contains('DEMO')) {
      await secureStorage.setDeviceID(authResponse.user.deviceId);
    }

    return authResponse;
  }

  // ==================== FORGOT PASSWORD FLOW ====================

  Future<Map<String, dynamic>> requestForgotPassword({
    required String phoneNumber,
  }) async {
    final devId = await secureStorage.getDeviceID();
    final response = await apiClient.post(
      ApiEndpoints.forgotPasswordRequest,
      data: {
        'phone_number': phoneNumber,
        'device_id': devId,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{};
  }

  Future<bool> verifyForgotPasswordOtp({
    required String sessionId,
    required String otpCode,
  }) async {
    await apiClient.post(
      ApiEndpoints.forgotPasswordOtp,
      data: {
        'session_id': sessionId,
        'otp_code': otpCode,
      },
    );
    return true;
  }

  Future<bool> resetForgotPassword({
    required String sessionId,
    required String newPassword,
  }) async {
    final devId = await secureStorage.getDeviceID();
    await apiClient.post(
      ApiEndpoints.forgotPasswordReset,
      data: {
        'session_id': sessionId,
        'new_password': newPassword,
        'device_id': devId,
      },
    );
    return true;
  }

  // ==================== SECURITY SELF-SERVICE ====================

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await apiClient.post(
      ApiEndpoints.changePassword,
      data: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
    return true;
  }

  Future<bool> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    await apiClient.post(
      ApiEndpoints.changePin,
      data: {
        'old_pin': oldPin,
        'new_pin': newPin,
      },
    );
    return true;
  }
}

