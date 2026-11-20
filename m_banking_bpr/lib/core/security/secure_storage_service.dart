import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_identity_service.dart';

class SecureStorageService {
  static const String _keyAccessToken = 'jwt_access_token';
  static const String _keyRefreshToken = 'jwt_refresh_token';
  static const String _keyPhoneNumber = 'user_phone_number';
  static const String _keyUsername = 'user_username';
  static const String _keyCIF = 'user_cif';
  static const String _keyFullName = 'user_full_name';
  static const String _keyPrimaryAccount = 'user_primary_account';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyBiometricRefreshToken = 'biometric_refresh_token';
  static const String _keyBiometricCif = 'biometric_cif';
  static const String _keyBiometricPhone = 'biometric_phone';
  static const String _keyBiometricFullName = 'biometric_full_name';
  static const String _keyBiometricPrimaryAccount = 'biometric_primary_account';
  static const String _keyDeviceKeyKind = 'device_key_kind';
  static const String _keyDeviceKeyRef = 'device_key_ref';

  final FlutterSecureStorage _storage;
  final DeviceIdentityService _deviceIdentityService;

  SecureStorageService({
    FlutterSecureStorage? storage,
    DeviceIdentityService? deviceIdentityService,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              // SR-8: a corrupted EncryptedSharedPreferences store (known on some vendor
              // ROMs / after a Keystore key invalidation) is reset instead of failing every
              // start forever. Only this app's secure values are lost (session tokens, key
              // state); the device identity (ANDROID_ID) and the Keystore device key are not
              // stored here, so the customer logs in again and the key is rediscovered.
              aOptions: AndroidOptions(encryptedSharedPreferences: true, resetOnError: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            ),
        _deviceIdentityService = deviceIdentityService ?? DeviceIdentityService();

  static const DeviceSecurityException _unavailable =
      DeviceSecurityException('STORAGE_UNAVAILABLE', 'Penyimpanan aman perangkat tidak dapat diakses');

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      throw _unavailable;
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      throw _unavailable;
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      throw _unavailable;
    }
  }

  Future<void> saveAuthData({
    required String accessToken,
    required String refreshToken,
    required String phoneNumber,
    String username = '',
    required String cif,
    required String fullName,
    required String primaryAccount,
  }) async {
    await _write(_keyAccessToken, accessToken);
    await _write(_keyRefreshToken, refreshToken);
    await _write(_keyPhoneNumber, phoneNumber);
    if (username.isNotEmpty) {
      await _write(_keyUsername, username);
    }
    await _write(_keyCIF, cif);
    await _write(_keyFullName, fullName);
    await _write(_keyPrimaryAccount, primaryAccount);
    if (await isBiometricEnabled() && refreshToken.isNotEmpty) {
      await _write(_keyBiometricRefreshToken, refreshToken);
    }
  }

  Future<String?> getAccessToken() async => await _read(_keyAccessToken);
  Future<String?> getRefreshToken() async => await _read(_keyRefreshToken);
  Future<String?> getPhoneNumber() async => await _read(_keyPhoneNumber);
  Future<String?> getUsername() async => await _read(_keyUsername);
  Future<void> saveUsername(String username) async => await _write(_keyUsername, username);
  Future<void> clearSavedLoginIdentifier() async {
    await _delete(_keyUsername);
    await _delete(_keyPhoneNumber);
  }
  Future<String?> getCIF() async => await _read(_keyCIF);
  Future<String?> getCif() async => await _read(_keyCIF);
  Future<String?> getFullName() async => await _read(_keyFullName);
  Future<String?> getPrimaryAccount() async => await _read(_keyPrimaryAccount);

  Future<void> clearAuthData() async {
    await _delete(_keyAccessToken);
    await _delete(_keyRefreshToken);
    await _delete(_keyCIF);
    await _delete(_keyFullName);
    await _delete(_keyPrimaryAccount);
    await _delete(_keyBiometricRefreshToken);
    await _delete(_keyBiometricCif);
    await _delete(_keyBiometricPhone);
    await _delete(_keyBiometricFullName);
    await _delete(_keyBiometricPrimaryAccount);
  }

  Future<void> clearSessionTokens() async {
    await _delete(_keyAccessToken);
    await _delete(_keyRefreshToken);
  }

  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _write(_keyBiometricEnabled, enabled ? 'true' : 'false');
  }

  Future<bool> isBiometricEnabled() async {
    final val = await _read(_keyBiometricEnabled);
    return val == 'true';
  }

  Future<void> saveBiometricCredentials({
    required String refreshToken,
    required String cif,
    required String phone,
    required String fullName,
    required String primaryAccount,
  }) async {
    await _write(_keyBiometricEnabled, 'true');
    await _write(_keyBiometricRefreshToken, refreshToken);
    await _write(_keyBiometricCif, cif);
    await _write(_keyBiometricPhone, phone);
    await _write(_keyBiometricFullName, fullName);
    await _write(_keyBiometricPrimaryAccount, primaryAccount);
  }

  Future<void> clearBiometricCredentials() async {
    await _delete(_keyBiometricEnabled);
    await _delete(_keyBiometricRefreshToken);
    await _delete(_keyBiometricCif);
    await _delete(_keyBiometricPhone);
    await _delete(_keyBiometricFullName);
    await _delete(_keyBiometricPrimaryAccount);
  }

  Future<String?> getBiometricRefreshToken() async => await _read(_keyBiometricRefreshToken);

  Future<void> clearBiometricRefreshToken() async => await _delete(_keyBiometricRefreshToken);
  Future<String?> getBiometricCif() async => await _read(_keyBiometricCif);
  Future<String?> getBiometricPhone() async => await _read(_keyBiometricPhone);
  Future<String?> getBiometricFullName() async => await _read(_keyBiometricFullName);
  Future<String?> getBiometricPrimaryAccount() async => await _read(_keyBiometricPrimaryAccount);

  DeviceIdentityService get deviceIdentityService => _deviceIdentityService;

  Future<String> getDeviceID() => _deviceIdentityService.canonicalId();

  Future<String?> getDeviceKeyKind() async => await _read(_keyDeviceKeyKind);
  Future<String?> getDeviceKeyRef() async => await _read(_keyDeviceKeyRef);

  Future<void> saveDeviceKeyState({required String kind, required String keyRef}) async {
    await _write(_keyDeviceKeyKind, kind);
    await _write(_keyDeviceKeyRef, keyRef);
  }

  Future<void> clearDeviceKeyState() async {
    await _delete(_keyDeviceKeyKind);
    await _delete(_keyDeviceKeyRef);
  }
}
