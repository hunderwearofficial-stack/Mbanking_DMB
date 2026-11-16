import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/services/terms_consent_store.dart';
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
        'terms_acceptance_id': TermsConsentStore.instance.acceptanceId ?? '',
      },
    );

    final authResponse = AuthResponseModel.fromJson(response);
    TermsConsentStore.instance.clear(); // linked to the customer by the backend

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

    // The device identifier is generated on the device only; it is never taken
    // from a server response (audit DMB-013).
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
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('Sesi biometrik telah berakhir. Silakan login menggunakan password untuk mengaktifkan kembali login biometrik.');
    }

    // The biometric prompt only unlocks the locally stored session; the server must
    // still accept the refresh token. There is NO offline fallback: a fabricated
    // local session (previously "bio_session_active") is never created (audit DMB-014).
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
      fullName: authResponse.user.fullName.isNotEmpty ? authResponse.user.fullName : fullName,
      primaryAccount: authResponse.user.primaryAccount.isNotEmpty ? authResponse.user.primaryAccount : primaryAcc,
    );
    await secureStorage.saveBiometricCredentials(
      refreshToken: authResponse.refreshToken,
      cif: authResponse.user.cif,
      phone: authResponse.user.phoneNumber,
      fullName: authResponse.user.fullName,
      primaryAccount: authResponse.user.primaryAccount,
    );
    return authResponse.user;
  }

  /// Explicit logout: revokes the server-side session, then clears local tokens
  /// including the biometric session token.
  Future<void> logout() async {
    try {
      await apiClient.post(ApiEndpoints.logout, data: {});
    } catch (_) {
      // Best effort: local tokens are cleared regardless.
    }
    await secureStorage.clearAuthData();
    await secureStorage.clearBiometricRefreshToken();
  }

  /// Session lock (e.g. inactivity timeout): clears the active tokens on screen but
  /// keeps the biometric session so the user can unlock with biometrics.
  Future<void> lockSession() async {
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
        'terms_acceptance_id': TermsConsentStore.instance.acceptanceId ?? '',
      },
    );

    final authResponse = AuthResponseModel.fromJson(response);
    TermsConsentStore.instance.clear();

    await secureStorage.saveAuthData(
      accessToken: authResponse.accessToken,
      refreshToken: authResponse.refreshToken,
      phoneNumber: authResponse.user.phoneNumber,
      cif: authResponse.user.cif,
      fullName: authResponse.user.fullName,
      primaryAccount: authResponse.user.primaryAccount,
    );

    // The device identifier is generated on the device only; it is never taken
    // from a server response (audit DMB-013).
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

