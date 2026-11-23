import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/security/device_binding_service.dart';
import '../../core/security/device_identity_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/services/terms_consent_store.dart';
import '../../core/utils/app_logger.dart';
import '../models/device_binding_model.dart';
import '../models/user_model.dart';

class AuthRepository {
  final ApiClient apiClient;
  final SecureStorageService secureStorage;

  AuthRepository({required this.apiClient, required this.secureStorage});

  DeviceBindingService get _binding => apiClient.deviceBinding;

  Future<dynamic> _lockedPost(String path, Map<String, dynamic> body) => apiClient.postInsideAuthLock(path, body);

  static const String _keyMissingMessage =
      'Kunci keamanan perangkat ini tidak ditemukan atau tidak berlaku lagi. Silakan verifikasi ulang perangkat melalui menu Lupa Password.';

  Future<Never> _rethrowDeviceError(Object e) async {
    if (e is ApiException && e.responseCode == '10' && await secureStorage.getDeviceKeyKind() == null) {
      throw ApiException(message: _keyMissingMessage, statusCode: e.statusCode, responseCode: e.responseCode);
    }
    throw e;
  }

  Future<void> _saveSession(AuthResponseModel auth) => secureStorage.saveAuthData(
        accessToken: auth.accessToken,
        refreshToken: auth.refreshToken,
        phoneNumber: auth.user.phoneNumber,
        username: auth.user.username,
        cif: auth.user.cif,
        fullName: auth.user.fullName,
        primaryAccount: auth.user.primaryAccount,
      );

  Future<AuthResponseModel> _enrollIfAllowed(AuthResponseModel auth) async {
    final st = auth.deviceBinding;
    if (st != null && st.mode.isNotEmpty && st.mode != 'off' && !st.enrolled) {
      await secureStorage.clearDeviceKeyState();
    }
    try {
      final res = await _binding.enrollIfAllowed(auth.deviceBinding, _lockedPost);
      if (res == null) return auth;
      final enrolled = AuthResponseModel.fromJson(res);
      if (enrolled.accessToken.isEmpty || enrolled.refreshToken.isEmpty) return auth;
      await _saveSession(enrolled);
      return enrolled;
    } catch (e) {
      logDebug('Pendaftaran kunci perangkat gagal: ${e is DeviceSecurityException ? e.code : e}');
      return auth;
    }
  }

  Future<AuthResponseModel> login({
    required String identifier,
    required String password,
  }) {
    return AuthSessionLock.instance.run(() async {
      final devId = await secureStorage.getDeviceID();
      final payload = <String, dynamic>{
        'username': identifier,
        'cif': identifier,
        'phone_number': identifier,
        'password': password,
        'device_id': devId,
        'terms_acceptance_id': TermsConsentStore.instance.acceptanceId ?? '',
      };
      final proof = await _binding.prove(
        post: _lockedPost,
        challengePath: ApiEndpoints.deviceChallenge,
        challengeBody: {'phone_number': identifier, 'device_id': devId},
        purpose: 'LOGIN',
        deviceId: devId,
      );
      if (proof != null) payload.addAll(proof.toJson());

      dynamic response;
      try {
        response = await _lockedPost(ApiEndpoints.login, payload);
      } catch (e) {
        await _rethrowDeviceError(e);
      }
      var authResponse = AuthResponseModel.fromJson(response as Map<String, dynamic>);
      TermsConsentStore.instance.clear(); // linked to the customer by the backend
      await _saveSession(authResponse);
      authResponse = await _enrollIfAllowed(authResponse);

      if (await secureStorage.isBiometricEnabled()) {
        await secureStorage.saveBiometricCredentials(
          refreshToken: authResponse.refreshToken,
          cif: authResponse.user.cif,
          phone: authResponse.user.phoneNumber,
          fullName: authResponse.user.fullName,
          primaryAccount: authResponse.user.primaryAccount,
        );
      }
      return authResponse;
    });
  }

  Future<AuthResponseModel> _refreshWith(String refreshToken) async {
    final devId = DeviceBindingService.deviceIdFromToken(refreshToken);
    if (devId == null) {
      throw ApiException(message: 'Sesi tidak valid. Silakan login kembali.', statusCode: 401, responseCode: '01');
    }
    Future<dynamic> post(String path, Map<String, dynamic> body) =>
        apiClient.postInsideAuthLock(path, body, headers: {'X-Device-ID': devId});
    final payload = <String, dynamic>{'refresh_token': refreshToken, 'device_id': devId};
    final proof = await _binding.prove(
      post: post,
      challengePath: ApiEndpoints.deviceChallenge,
      challengeBody: {'refresh_token': refreshToken, 'device_id': devId},
      purpose: 'REFRESH',
      deviceId: devId,
    );
    if (proof != null) payload.addAll(proof.toJson());
    dynamic response;
    try {
      response = await post(ApiEndpoints.refresh, payload);
    } catch (e) {
      await _rethrowDeviceError(e);
    }
    return AuthResponseModel.fromJson(response as Map<String, dynamic>);
  }

  Future<UserModel> loginWithBiometric() {
    return AuthSessionLock.instance.run(() async {
      final isBio = await secureStorage.isBiometricEnabled();
      if (!isBio) {
        throw Exception('Login Biometrik belum diaktifkan.');
      }

      final refreshToken = await secureStorage.getBiometricRefreshToken() ?? await secureStorage.getRefreshToken();
      final cif = await secureStorage.getBiometricCif() ?? await secureStorage.getCIF() ?? '';
      final phone = await secureStorage.getBiometricPhone() ?? await secureStorage.getPhoneNumber() ?? '';
      final fullName = await secureStorage.getBiometricFullName() ?? await secureStorage.getFullName() ?? 'Nasabah Bank DMB';
      final primaryAcc = await secureStorage.getBiometricPrimaryAccount() ?? await secureStorage.getPrimaryAccount() ?? '';

      if (cif.isEmpty && phone.isEmpty) {
        throw Exception('Kredensial biometrik belum tersimpan. Silakan login menggunakan password sekali lagi.');
      }
      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception('Sesi biometrik telah berakhir. Silakan login menggunakan password untuk mengaktifkan kembali login biometrik.');
      }

      final authResponse = await _refreshWith(refreshToken);
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
    });
  }

  Future<void> logout() {
    return AuthSessionLock.instance.run(() async {
      try {
        await apiClient.postInsideAuthLock(ApiEndpoints.logout, {});
      } catch (_) {
      }
      await secureStorage.clearAuthData();
      await secureStorage.clearBiometricRefreshToken();
    });
  }

  Future<void> lockSession() => AuthSessionLock.instance.run(() => secureStorage.clearAuthData());

  Future<bool> isLoggedIn() async {
    return await secureStorage.hasValidToken();
  }

  Future<AuthResponseModel?> refreshSession() {
    return AuthSessionLock.instance.run(() async {
      final refreshToken = await secureStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return null;
      }
      final authResponse = await _refreshWith(refreshToken);
      await _saveSession(authResponse);
      return authResponse;
    });
  }

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

  /// Verifies the activation OTP. The customer data (name, CIF, suggested username) is
  /// only released by the server after this step (audit E-04).
  Future<Map<String, dynamic>> verifyActivationOtp({
    required String sessionId,
    required String otpCode,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.activateOtp,
      data: {
        'session_id': sessionId,
        'otp_code': otpCode,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{};
  }

  Future<AuthResponseModel> completeActivation({
    required String sessionId,
    String username = '',
    required String password,
    required String pin,
  }) {
    return AuthSessionLock.instance.run(() async {
      final devId = await secureStorage.getDeviceID();
      final response = await _lockedPost(ApiEndpoints.activateSetup, {
        'session_id': sessionId,
        'username': username,
        'password': password,
        'pin': pin,
        'device_id': devId,
        'terms_acceptance_id': TermsConsentStore.instance.acceptanceId ?? '',
      });
      var authResponse = AuthResponseModel.fromJson(response as Map<String, dynamic>);
      TermsConsentStore.instance.clear();
      await _saveSession(authResponse);
      authResponse = await _enrollIfAllowed(authResponse);
      return authResponse;
    });
  }

  Future<Map<String, dynamic>> requestForgotPassword({
    required String phoneNumber,
  }) async {
    String devId;
    try {
      devId = await secureStorage.getDeviceID();
    } on DeviceSecurityException catch (e) {
      if (e.code != 'DEVICE_ID_CORRUPT') rethrow;
      devId = (await secureStorage.deviceIdentityService.resetCorruptIdentity()).deviceId;
    }
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
    await secureStorage.clearDeviceKeyState();
    return true;
  }

  Future<void> _signedPost(String path, String purpose, Map<String, dynamic> body) async {
    final token = await secureStorage.getAccessToken();
    final devId = DeviceBindingService.deviceIdFromToken(token) ?? await secureStorage.getDeviceID();
    Future<dynamic> post(String p, Map<String, dynamic> b) => apiClient.post(p, data: b);
    final proof = await _binding.proveSession(post, purpose, devId, context: DeviceIdentityService.operationContext(purpose));
    try {
      await apiClient.post(path, data: {...body, if (proof != null) ...proof.toJson()});
    } catch (e) {
      await _rethrowDeviceError(e);
    }
  }

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _signedPost(ApiEndpoints.changePassword, 'CHANGE_PASSWORD', {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
    return true;
  }

  Future<bool> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    await _signedPost(ApiEndpoints.changePin, 'CHANGE_PIN', {
      'old_pin': oldPin,
      'new_pin': newPin,
    });
    return true;
  }

  Future<DeviceBindingStatusModel> deviceStatus() async {
    final res = await apiClient.get(ApiEndpoints.deviceStatus);
    return DeviceBindingStatusModel.fromJson(res is Map<String, dynamic> ? res : const {});
  }
}
