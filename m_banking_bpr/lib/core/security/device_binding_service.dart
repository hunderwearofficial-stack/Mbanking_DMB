import 'dart:async';
import 'dart:convert';

import '../../data/models/device_binding_model.dart';
import '../constants/api_endpoints.dart';
import '../network/api_exception.dart';
import '../utils/app_logger.dart';
import 'device_identity_service.dart';
import 'secure_storage_service.dart';

class AuthSessionLock {
  AuthSessionLock._();
  static final AuthSessionLock instance = AuthSessionLock._();

  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() body) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) async {
      try {
        return await body();
      } finally {
        done.complete();
      }
    });
  }

  Future<void> get idle => _tail;
}

class DeviceProof {
  final String challengeId;
  final String signature; // ES256 DER signature or App Attest assertion (base64)

  const DeviceProof(this.challengeId, this.signature);

  Map<String, String> toJson() => {'device_challenge_id': challengeId, 'device_signature': signature};
}

typedef DevicePost = Future<dynamic> Function(String path, Map<String, dynamic> body);

const String keyKindES256 = 'es256';
const String keyKindAppAttest = 'appattest';

class DeviceBindingService {
  final SecureStorageService storage;
  final bool Function() isIOS;

  DeviceBindingService({required this.storage, required this.isIOS});

  DeviceIdentityService get identity => storage.deviceIdentityService;

  static String? deviceIdFromToken(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final id = payload is Map ? payload['device_id'] : null;
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _map(dynamic res) {
    if (res is Map<String, dynamic>) {
      final data = res['data'];
      return data is Map<String, dynamic> ? data : res;
    }
    return const {};
  }

  Future<DeviceProof?> prove({
    required DevicePost post,
    required String challengePath,
    required Map<String, dynamic> challengeBody,
    required String purpose,
    required String deviceId,
    String context = '',
  }) async {
    final kind = await resolveKeyKind();
    if (kind == null) return null;
    try {
      final ch = DeviceChallengeResponseModel.fromJson(_map(await post(challengePath, {...challengeBody, 'purpose': purpose})));
      if (ch.challengeId.isEmpty || ch.nonce.isEmpty) return null;
      final msg = utf8.encode(DeviceIdentityService.buildSigningMessage(
          purpose: purpose, challengeId: ch.challengeId, nonce: ch.nonce, deviceId: deviceId, context: context));
      final sig = kind == keyKindAppAttest ? await identity.appAttestAssert(message: msg) : await identity.signRawBytes(bytes: msg);
      return DeviceProof(ch.challengeId, sig);
    } on DeviceSecurityException catch (e) {
      logDebug('Bukti kunci perangkat tidak dapat dibuat: ${e.code}');
      return null;
    } on ApiException catch (e) {
      logDebug('Challenge perangkat ditolak: ${e.responseCode}');
      return null;
    }
  }

  /// Kind of the device key of this installation. The stored value is used first; when the
  /// secure storage was reset or is unreadable (SR-8), the key is rediscovered from the
  /// native key store (Keystore / Secure Enclave / App Attest key id), so a storage reset
  /// does not force an OTP re-binding. No key is ever created here.
  Future<String?> resolveKeyKind() async {
    try {
      final stored = await storage.getDeviceKeyKind();
      if (stored != null) return stored;
    } on DeviceSecurityException {
      // unreadable storage: fall through to the native key store
    }
    try {
      if (isIOS() && await identity.appAttestKeyExists()) return keyKindAppAttest;
      if ((await identity.getKeyInfo()).exists) return keyKindES256;
    } on DeviceSecurityException {
      return null;
    }
    return null;
  }

  Future<DeviceProof?> proveSession(DevicePost post, String purpose, String deviceId, {String context = ''}) =>
      prove(post: post, challengePath: ApiEndpoints.deviceSessionChallenge, challengeBody: const {}, purpose: purpose,
          deviceId: deviceId, context: context);

  static Future<Map<String, dynamic>?>? _enrolling;

  Future<Map<String, dynamic>?> enrollIfAllowed(DeviceBindingStatusModel? status, DevicePost post) {
    if (status == null || status.mode == 'off' || status.enrolled || !status.isEnrollmentAllowed) {
      return Future.value(null);
    }
    return _enrolling ??= _enroll(post).whenComplete(() => _enrolling = null);
  }

  Future<Map<String, dynamic>?> _enroll(DevicePost post) async {
    final ident = await identity.getDeviceIdentity();
    final ch = DeviceChallengeResponseModel.fromJson(_map(await post(ApiEndpoints.deviceSessionChallenge, {'purpose': 'ENROLL'})));
    if (ch.challengeId.isEmpty || ch.nonce.isEmpty) {
      throw const DeviceSecurityException('ENROLL_CHALLENGE_INVALID', 'Challenge pendaftaran tidak valid');
    }
    final lastRef = await storage.getDeviceKeyRef();
    Map<String, dynamic> body;
    String kind, ref;

    if (isIOS() && await identity.appAttestSupported()) {
      final keyId = await identity.appAttestGenerateKey();
      if (keyId == lastRef) {
        throw const DeviceSecurityException('KEY_REUSED', 'Kunci perangkat tidak boleh dipakai ulang');
      }
      final msg = utf8.encode(DeviceIdentityService.buildSigningMessage(
          purpose: 'ENROLL', challengeId: ch.challengeId, nonce: ch.nonce, deviceId: ident.deviceId,
          context: DeviceIdentityService.enrollContext(keyId, ident.deviceId)));
      body = {
        'device_id': ident.deviceId,
        'platform': 'ios',
        'attestation_format': 'apple-appattest',
        'app_attest_key_id': keyId,
        'attestation_object': await identity.appAttestAttest(message: msg),
        'security_level': 'SECURE_ENCLAVE',
        'challenge_id': ch.challengeId,
      };
      kind = keyKindAppAttest;
      ref = keyId;
    } else {
      final android = ident.platform == 'android';
      final key = await identity.generateKey(attestationChallenge: android ? ch.nonce : null);
      final fp = DeviceIdentityService.computeFingerprint(key.publicKey!);
      if (fp == lastRef) {
        throw const DeviceSecurityException('KEY_REUSED', 'Kunci perangkat tidak boleh dipakai ulang');
      }
      final msg = utf8.encode(DeviceIdentityService.buildSigningMessage(
          purpose: 'ENROLL', challengeId: ch.challengeId, nonce: ch.nonce, deviceId: ident.deviceId,
          context: DeviceIdentityService.enrollContext(fp, ident.deviceId)));
      body = {
        'device_id': ident.deviceId,
        'platform': ident.platform,
        'attestation_format': android ? 'android-key' : 'none',
        'public_key': key.publicKey,
        'security_level': key.securityLevel ?? '',
        if (android) 'attestation_chain': key.attestationChain,
        'challenge_id': ch.challengeId,
        'signature': await identity.signRawBytes(bytes: msg),
      };
      kind = keyKindES256;
      ref = fp;
    }
    final res = _map(await post(ApiEndpoints.deviceEnroll, body));
    await storage.saveDeviceKeyState(kind: kind, keyRef: ref);
    return res;
  }
}
