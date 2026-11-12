import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const MethodChannel _deviceChannel = MethodChannel('com.bprdmb.mbanking/device_info');
  static const String _keyAccessToken = 'jwt_access_token';
  static const String _keyRefreshToken = 'jwt_refresh_token';
  static const String _keyDeviceID = 'app_device_id';
  static const String _keyPhoneNumber = 'user_phone_number';
  static const String _keyCIF = 'user_cif';
  static const String _keyFullName = 'user_full_name';
  static const String _keyPrimaryAccount = 'user_primary_account';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyBiometricRefreshToken = 'biometric_refresh_token';
  static const String _keyBiometricCif = 'biometric_cif';
  static const String _keyBiometricPhone = 'biometric_phone';
  static const String _keyBiometricFullName = 'biometric_full_name';
  static const String _keyBiometricPrimaryAccount = 'biometric_primary_account';
  static const String _keyFCMToken = 'fcm_device_token';

  final FlutterSecureStorage _storage;

  // In-memory fallback if platform secure storage is unavailable
  final Map<String, String> _memoryFallback = {};

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      _memoryFallback[key] = value;
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key) ?? _memoryFallback[key];
    } catch (_) {
      return _memoryFallback[key];
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    _memoryFallback.remove(key);
  }

  // --- Auth Token Management ---

  Future<void> saveAuthData({
    required String accessToken,
    required String refreshToken,
    required String phoneNumber,
    required String cif,
    required String fullName,
    required String primaryAccount,
  }) async {
    await _write(_keyAccessToken, accessToken);
    await _write(_keyRefreshToken, refreshToken);
    await _write(_keyPhoneNumber, phoneNumber);
    await _write(_keyCIF, cif);
    await _write(_keyFullName, fullName);
    await _write(_keyPrimaryAccount, primaryAccount);
  }

  Future<String?> getAccessToken() async => await _read(_keyAccessToken);
  Future<String?> getRefreshToken() async => await _read(_keyRefreshToken);
  Future<String?> getPhoneNumber() async => await _read(_keyPhoneNumber);
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
  }

  Future<void> clearSessionTokens() async {
    await _delete(_keyAccessToken);
    await _delete(_keyRefreshToken);
  }

  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // --- Biometric Authentication Management ---

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
  Future<String?> getBiometricCif() async => await _read(_keyBiometricCif);
  Future<String?> getBiometricPhone() async => await _read(_keyBiometricPhone);
  Future<String?> getBiometricFullName() async => await _read(_keyBiometricFullName);
  Future<String?> getBiometricPrimaryAccount() async => await _read(_keyBiometricPrimaryAccount);

  // --- Device Binding Identifier ---

  Future<String> getDeviceID() async {
    // 1. Always prioritize fetching the real hardware device ID from native Android MethodChannel
    try {
      final hwId = await _deviceChannel.invokeMethod<String>('getHardwareDeviceId');
      if (hwId != null && hwId.trim().isNotEmpty && !hwId.contains('DEMO')) {
        final cleanHwId = hwId.trim();
        await _write(_keyDeviceID, cleanHwId);
        return cleanHwId;
      }
    } catch (_) {
      // Platform channel unavailable (e.g. non-Android/web/test)
    }

    // 2. Read existing cached device ID
    String? deviceID = await _read(_keyDeviceID);
    if (deviceID == null || deviceID.isEmpty || deviceID.contains('DEMO')) {
      final rand = Random.secure();
      final hex = List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join().toUpperCase();
      deviceID = 'ANDROID-SM-$hex';
      await _write(_keyDeviceID, deviceID);
    }
    return deviceID;
  }

  Future<void> setDeviceID(String deviceID) async {
    if (deviceID.isNotEmpty && !deviceID.contains('DEMO')) {
      await _write(_keyDeviceID, deviceID);
    }
  }

  // --- FCM Device Push Token ---

  Future<void> saveFCMToken(String token) async {
    if (token.isNotEmpty) {
      await _write(_keyFCMToken, token);
    }
  }

  Future<String?> getFCMToken() async {
    return await _read(_keyFCMToken);
  }
}

