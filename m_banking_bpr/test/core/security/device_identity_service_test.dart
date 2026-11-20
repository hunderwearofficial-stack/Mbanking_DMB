import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/security/device_binding_service.dart';
import 'package:m_banking_bpr/core/security/device_identity_service.dart';

import '../../helpers/device_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('protocol vectors (identical to internal/devicebind TestSigningMessageVector)', () {
    test('signing message', () {
      expect(
        DeviceIdentityService.buildSigningMessage(purpose: 'LOGIN', challengeId: 'c1', nonce: 'n1', deviceId: 'and-00a1b2c3d4e5f607'),
        'DMB-DEVICE-BINDING-V1\nLOGIN\nc1\nn1\nand-00a1b2c3d4e5f607\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('enroll / operation contexts and fingerprint', () {
      expect(DeviceIdentityService.enrollContext('fp', 'and-1'), 'fp\nand-1');
      expect(DeviceIdentityService.operationContext('CHANGE_PIN'), 'operation=CHANGE_PIN');
      expect(DeviceIdentityService.computeFingerprint(base64Encode(utf8.encode('abc'))),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('canonical identity (DB-H1, DB-H3)', () {
    test('only canonical identifiers of the reported platform are accepted', () {
      expect(DeviceIdentityInfo.fromMap({'device_id': 'and-00a1b2c3d4e5f607', 'platform': 'android'}).deviceId, 'and-00a1b2c3d4e5f607');
      expect(DeviceIdentityInfo.fromMap({'device_id': 'ios-1b4e28ba-2fa1-41d2-883f-0016d3cca427', 'platform': 'ios'}).platform, 'ios');
      for (final bad in [
        {'device_id': 'ANDROID-SM-1A2B3C4D', 'platform': 'android'}, // previous app format
        {'device_id': 'SAMSUNG-SM-A515F-1A2B3C4D', 'platform': 'android'},
        {'device_id': 'and-00a1b2c3d4e5f607', 'platform': 'ios'},
        {'device_id': '', 'platform': 'android'},
      ]) {
        expect(() => DeviceIdentityInfo.fromMap(bad), throwsA(isA<DeviceSecurityException>()));
      }
    });

    test('native failure is an error, not a fallback, and is not cached', () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.native.identityError = 'KEYCHAIN_LOCKED';
      await expectLater(h.storage.getDeviceID(), throwsA(isA<DeviceSecurityException>().having((e) => e.code, 'code', 'KEYCHAIN_LOCKED')));
      h.native.identityError = null;
      expect(await h.storage.getDeviceID(), 'and-0123456789abcdef');
      await h.storage.getDeviceID();
      expect(h.native.count('getDeviceIdentity'), 2, reason: 'success cached per process, error not cached');
    });

    test('platform without the native channel has no identity', () async {
      DeviceIdentityService.resetCacheForTest();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(FakeNative.channel, null);
      final svc = DeviceIdentityService();
      await expectLater(svc.canonicalId(), throwsA(isA<DeviceSecurityException>()));
    });

    test('no code path in lib/core/security creates an identifier (grep gate)', () {
      for (final f in Directory('lib/core/security').listSync().whereType<File>()) {
        final src = f.readAsStringSync();
        expect(src.contains('ANDROID-SM-'), isFalse, reason: f.path);
        expect(src.contains('Random'), isFalse, reason: f.path);
        expect(src.contains('_memoryFallback'), isFalse, reason: f.path);
      }
    });
  });

  group('secure storage (DB-H1, L4)', () {
    test('storage failure is reported, never kept in memory', () async {
      final h = Harness(secureStorage: BrokenSecureStorage());
      addTearDown(h.dispose);
      await expectLater(
        h.storage.saveAuthData(accessToken: 'a', refreshToken: 'r', phoneNumber: '', cif: '', fullName: '', primaryAccount: ''),
        throwsA(isA<DeviceSecurityException>().having((e) => e.code, 'code', 'STORAGE_UNAVAILABLE')),
      );
      await expectLater(h.storage.getAccessToken(), throwsA(isA<DeviceSecurityException>()));
    });

    test('the identifier of the previous app version is never read, written or deleted', () async {
      final h = Harness(initialStorage: {'app_device_id': 'SAMSUNG-SM-A515F-1A2B3C4D'});
      addTearDown(h.dispose);
      expect(await h.storage.getDeviceID(), 'and-0123456789abcdef');
      await h.storage.clearAuthData();
      expect(await const FlutterSecureStorage().read(key: 'app_device_id'), 'SAMSUNG-SM-A515F-1A2B3C4D');
    });
  });

  test('session device id comes from the token claim', () {
    expect(DeviceBindingService.deviceIdFromToken(testJwt('SAMSUNG-SM-A515F-1A2B3C4D')), 'SAMSUNG-SM-A515F-1A2B3C4D');
    expect(DeviceBindingService.deviceIdFromToken('not.a.jwt!'), isNull);
    expect(DeviceBindingService.deviceIdFromToken(null), isNull);
  });

  test('generateKey passes the server nonce as attestation challenge (Android)', () async {
    final h = Harness();
    addTearDown(h.dispose);
    final key = await DeviceIdentityService().generateKey(attestationChallenge: 'nonce-xyz');
    expect(key.attestationChain.first, 'leaf-nonce-xyz');
    expect((h.native.calls.last.arguments as Map)['attestation_challenge'], 'nonce-xyz');
  });

  test('PlatformException is mapped to a structured error', () async {
    final h = Harness();
    addTearDown(h.dispose);
    h.native.keyError = 'INSECURE_HARDWARE';
    await expectLater(DeviceIdentityService().generateKey(attestationChallenge: 'n'),
        throwsA(isA<DeviceSecurityException>().having((e) => e.code, 'code', 'INSECURE_HARDWARE')));
  });
}
