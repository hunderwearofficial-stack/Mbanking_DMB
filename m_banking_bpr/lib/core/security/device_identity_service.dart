import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class DeviceIdentityInfo {
  final String deviceId;
  final String platform;

  const DeviceIdentityInfo({required this.deviceId, required this.platform});

  static final RegExp _android = RegExp(r'^and-[0-9a-f]{16}$');
  static final RegExp _ios = RegExp(r'^ios-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  factory DeviceIdentityInfo.fromMap(Map<dynamic, dynamic> map) {
    final id = (map['device_id'] ?? '').toString();
    final platform = (map['platform'] ?? '').toString();
    final ok = (platform == 'android' && _android.hasMatch(id)) || (platform == 'ios' && _ios.hasMatch(id));
    if (!ok) {
      throw const DeviceSecurityException('DEVICE_ID_INVALID', 'Identitas perangkat tidak valid');
    }
    return DeviceIdentityInfo(deviceId: id, platform: platform);
  }
}

class DeviceKeyInfo {
  final bool exists;
  final String? publicKey; // SubjectPublicKeyInfo DER, base64 (Android / iOS SE key)
  final String? securityLevel;
  final List<String> attestationChain; // Android Key Attestation, leaf first

  const DeviceKeyInfo({required this.exists, this.publicKey, this.securityLevel, this.attestationChain = const []});

  factory DeviceKeyInfo.fromMap(Map<dynamic, dynamic> map) {
    final chain = map['attestation_chain'];
    return DeviceKeyInfo(
      exists: map['exists'] == true,
      publicKey: map['public_key']?.toString(),
      securityLevel: map['security_level']?.toString(),
      attestationChain: chain is List ? chain.map((e) => e.toString()).toList() : const [],
    );
  }
}

class DeviceSecurityException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  const DeviceSecurityException(this.code, this.message, [this.details]);

  String get userMessage {
    switch (code) {
      case 'KEYCHAIN_LOCKED':
        return 'Identitas perangkat belum dapat dibaca. Buka kunci perangkat Anda lalu coba kembali.';
      case 'STORAGE_UNAVAILABLE':
      case 'KEYCHAIN_UNAVAILABLE':
        return 'Penyimpanan aman perangkat tidak dapat diakses. Mulai ulang aplikasi lalu coba kembali.';
      case 'DEVICE_ID_CORRUPT':
        return 'Identitas perangkat perlu diverifikasi ulang. Silakan gunakan menu Lupa Password.';
      default:
        return 'Identitas perangkat tidak dapat diperoleh. Mobile DMB tidak dapat digunakan pada perangkat ini.';
    }
  }

  @override
  String toString() => userMessage;
}

class DeviceIdentityService {
  static const String channelName = 'com.bprdmb.mbanking/device_identity';
  static const String defaultAlias = 'dmb_device_key_primary';
  static const String signingFormat = 'DMB-DEVICE-BINDING-V1';

  final MethodChannel _channel;

  DeviceIdentityService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static DeviceIdentityInfo? _cached;
  static Future<DeviceIdentityInfo>? _inflight;

  static void resetCacheForTest() {
    _cached = null;
    _inflight = null;
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DeviceSecurityException(e.code, e.message ?? e.code, e.details);
    } on MissingPluginException {
      throw const DeviceSecurityException('DEVICE_ID_UNAVAILABLE', 'Platform tidak mendukung identitas perangkat');
    }
  }

  Future<DeviceIdentityInfo> getDeviceIdentity() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _inflight ??= () async {
      try {
        final res = await _invoke<Map<dynamic, dynamic>>('getDeviceIdentity');
        if (res == null) {
          throw const DeviceSecurityException('DEVICE_ID_UNAVAILABLE', 'Identitas perangkat kosong');
        }
        final info = DeviceIdentityInfo.fromMap(res);
        _cached = info;
        return info;
      } finally {
        _inflight = null;
      }
    }();
  }

  Future<String> canonicalId() async => (await getDeviceIdentity()).deviceId;

  Future<DeviceIdentityInfo> resetCorruptIdentity() async {
    final res = await _invoke<Map<dynamic, dynamic>>('resetCorruptDeviceIdentity');
    if (res == null) {
      throw const DeviceSecurityException('DEVICE_ID_UNAVAILABLE', 'Identitas perangkat kosong');
    }
    final info = DeviceIdentityInfo.fromMap(res);
    _cached = info;
    return info;
  }

  Future<DeviceKeyInfo> getKeyInfo({String alias = defaultAlias}) async {
    final res = await _invoke<Map<dynamic, dynamic>>('getKeyInfo', {'alias': alias});
    return res == null ? const DeviceKeyInfo(exists: false) : DeviceKeyInfo.fromMap(res);
  }

  Future<DeviceKeyInfo> generateKey({String alias = defaultAlias, String? attestationChallenge}) async {
    final res = await _invoke<Map<dynamic, dynamic>>('generateKey', {
      'alias': alias,
      if (attestationChallenge != null) 'attestation_challenge': attestationChallenge,
    });
    if (res == null) {
      throw const DeviceSecurityException('KEY_GENERATION_FAILED', 'Gagal membuat kunci perangkat');
    }
    final info = DeviceKeyInfo.fromMap(res);
    if (!info.exists || info.publicKey == null || info.publicKey!.isEmpty) {
      throw const DeviceSecurityException('KEY_GENERATION_FAILED', 'Kunci perangkat tidak lengkap');
    }
    return info;
  }

  Future<String> signRawBytes({required List<int> bytes, String alias = defaultAlias}) async {
    final sig = await _invoke<String>('sign', {'alias': alias, 'message': base64Encode(bytes)});
    if (sig == null || sig.isEmpty) {
      throw const DeviceSecurityException('SIGN_FAILED', 'Tanda tangan perangkat kosong');
    }
    return sig;
  }

  Future<bool> deleteKey({String alias = defaultAlias}) async =>
      (await _invoke<bool>('deleteKey', {'alias': alias})) == true;

  Future<bool> appAttestSupported() async => (await _invoke<bool>('appAttestSupported')) == true;

  Future<String> appAttestGenerateKey({String alias = defaultAlias}) async {
    final res = await _invoke<Map<dynamic, dynamic>>('appAttestGenerateKey', {'alias': alias});
    final keyId = res?['key_id']?.toString() ?? '';
    if (keyId.isEmpty) {
      throw const DeviceSecurityException('APP_ATTEST_FAILED', 'Kunci App Attest tidak dibuat');
    }
    return keyId;
  }

  Future<String> appAttestAttest({required List<int> message, String alias = defaultAlias}) async {
    final res = await _invoke<Map<dynamic, dynamic>>('appAttestAttest', {'alias': alias, 'message': base64Encode(message)});
    final obj = res?['attestation_object']?.toString() ?? '';
    if (obj.isEmpty) {
      throw const DeviceSecurityException('APP_ATTEST_FAILED', 'Attestation App Attest kosong');
    }
    return obj;
  }

  Future<String> appAttestAssert({required List<int> message, String alias = defaultAlias}) async {
    final a = await _invoke<String>('appAttestAssert', {'alias': alias, 'message': base64Encode(message)});
    if (a == null || a.isEmpty) {
      throw const DeviceSecurityException('APP_ATTEST_FAILED', 'Assertion App Attest kosong');
    }
    return a;
  }

  Future<bool> appAttestKeyExists({String alias = defaultAlias}) async {
    final res = await _invoke<Map<dynamic, dynamic>>('appAttestKeyInfo', {'alias': alias});
    return res?['exists'] == true;
  }

  static String contextDigest(String context) => sha256.convert(utf8.encode(context)).toString();

  static String buildSigningMessage({
    required String purpose,
    required String challengeId,
    required String nonce,
    required String deviceId,
    String context = '',
  }) =>
      '$signingFormat\n$purpose\n$challengeId\n$nonce\n$deviceId\n${contextDigest(context)}';

  static String computeFingerprint(String publicKeyBase64) => sha256.convert(base64Decode(publicKeyBase64.trim())).toString();

  static String enrollContext(String keyRef, String deviceId) => '$keyRef\n$deviceId';

  static String operationContext(String purpose) => 'operation=$purpose';
}
