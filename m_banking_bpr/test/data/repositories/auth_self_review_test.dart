import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/constants/api_endpoints.dart';
import 'package:m_banking_bpr/core/security/device_binding_service.dart';
import 'package:m_banking_bpr/core/security/device_identity_service.dart';
import 'package:m_banking_bpr/data/repositories/auth_repository.dart';

import '../../helpers/device_test_harness.dart';

const andId = 'and-0123456789abcdef';

Map<String, dynamic> challenge(String purpose) =>
    ok({'challenge_id': '11111111-2222-4333-8444-555555555559', 'nonce': 'nonce-9', 'purpose': purpose});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Harness? h;
  tearDown(() {
    h?.dispose();
    h = null;
  });

  group('SR-1 no deadlock inside AuthSessionLock', () {
    test('a 401 during enrollment ends the operation instead of waiting for the lock', () async {
      final hh = h = Harness();
      final repo = AuthRepository(apiClient: hh.api, secureStorage: hh.storage);
      hh.backend.routes[ApiEndpoints.login] = (r) => (200, ok(authData(andId, tag: 'login', binding: {
                'mode': 'dual', 'enrolled': false, 'enrollment': 'ALLOWED', 'session_device_id': andId,
              })));
      // The session is revoked while enrolling: the enrollment requests answer 401.
      hh.backend.routes[ApiEndpoints.deviceSessionChallenge] = (r) => (401, apiFail('01', 'Sesi Anda telah berakhir'));
      hh.backend.routes[ApiEndpoints.refresh] = (r) => (200, ok(authData(andId, tag: 'refreshed')));

      // Before the fix this future never completed (refresh waited for the lock held by login).
      final auth = await repo.login(identifier: '0812', password: 'x').timeout(const Duration(seconds: 5));
      expect(auth.accessToken, testJwt(andId, tag: 'acc-login'));
      expect(hh.backend.to(ApiEndpoints.refresh), isEmpty, reason: 'no refresh from inside the lock');
      expect(hh.unauthorized, 0, reason: 'the session is not cleared from inside the lock');
      expect(await hh.storage.getDeviceKeyKind(), isNull);
    });

    test('a 401 for a request outside the lock still refreshes once', () async {
      final hh = h = Harness(initialStorage: {
        'jwt_access_token': testJwt(andId, tag: 'old'),
        'jwt_refresh_token': testJwt(andId, tag: 'r-old'),
      });
      var calls = 0;
      hh.backend.routes[ApiEndpoints.balance] = (r) => (++calls == 1 ? (401, apiFail('01', 'expired')) : (200, ok({'b': 1})));
      hh.backend.routes[ApiEndpoints.refresh] = (r) => (200, ok(authData(andId, tag: 'new')));
      await hh.api.get(ApiEndpoints.balance).timeout(const Duration(seconds: 5));
      expect(hh.backend.to(ApiEndpoints.refresh).length, 1);
      expect(await hh.storage.getAccessToken(), testJwt(andId, tag: 'acc-new'));
    });
  });

  group('SR-8 secure storage reset / failure', () {
    test('after a storage reset the enrolled Keystore key is rediscovered (no OTP needed)', () async {
      final hh = h = Harness(); // storage empty: device_key_kind lost
      hh.native.keyExists = true; // the Keystore key survives (it is not stored there)
      expect(await hh.api.deviceBinding.resolveKeyKind(), keyKindES256);
      final repo = AuthRepository(apiClient: hh.api, secureStorage: hh.storage);
      hh.backend.routes[ApiEndpoints.deviceChallenge] = (r) => (200, challenge('LOGIN'));
      hh.backend.routes[ApiEndpoints.login] = (r) => (200, ok(authData(andId, binding: {
                'mode': 'dual', 'enrolled': true, 'enrollment': 'NOT_NEEDED', 'session_device_id': andId,
              })));
      await repo.login(identifier: '0812', password: 'x');
      final body = hh.backend.to(ApiEndpoints.login).single.body as Map;
      expect(body['device_signature'], isNotNull, reason: 'login is signed with the rediscovered key');
    });

    test('iOS: App Attest key id is rediscovered from the Keychain', () async {
      final hh = h = Harness(ios: true);
      hh.native.appAttestKeyStored = true;
      expect(await hh.api.deviceBinding.resolveKeyKind(), keyKindAppAttest);
    });

    test('unreadable storage: no fallback identity or token, the request is not sent', () async {
      final hh = h = Harness(secureStorage: BrokenSecureStorage());
      await expectLater(hh.api.get(ApiEndpoints.balance), throwsA(anything));
      expect(hh.backend.requests, isEmpty);
      // The key kind falls back to the native key store only (never to memory).
      hh.native.keyExists = false;
      expect(await hh.api.deviceBinding.resolveKeyKind(), isNull);
    });

    test('no key anywhere: no proof is invented', () async {
      final hh = h = Harness();
      expect(await DeviceBindingService(storage: hh.storage, isIOS: () => false).resolveKeyKind(), isNull);
      expect(hh.native.count('generateKey'), 0);
      expect(DeviceIdentityService.defaultAlias, 'dmb_device_key_primary');
    });
  });
}
