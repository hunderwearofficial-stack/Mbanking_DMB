import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/constants/api_endpoints.dart';
import 'package:m_banking_bpr/core/network/api_exception.dart';
import 'package:m_banking_bpr/core/security/device_binding_service.dart';
import 'package:m_banking_bpr/data/models/device_binding_model.dart';
import 'package:m_banking_bpr/data/repositories/auth_repository.dart';

import '../../helpers/device_test_harness.dart';

const legacy = 'SAMSUNG-SM-A515F-1A2B3C4D';
const andId = 'and-0123456789abcdef';

Map<String, dynamic> challenge(String purpose, [int n = 1]) =>
    ok({'challenge_id': '11111111-2222-4333-8444-55555555555$n', 'nonce': 'nonce-$n', 'purpose': purpose});

Map<String, dynamic> allowed(String dev) => {'mode': 'dual', 'enrolled': false, 'enrollment': 'ALLOWED', 'session_device_id': dev};
Map<String, dynamic> enrolled(String dev) =>
    {'mode': 'dual', 'enrolled': true, 'enrollment': 'NOT_NEEDED', 'attestation_status': 'HARDWARE_VERIFIED', 'session_device_id': dev};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Harness? current;
  late Harness h;
  late AuthRepository repo;

  void setup({Map<String, String> storage = const {}, bool ios = false}) {
    h = current = Harness(initialStorage: storage, ios: ios);
    repo = AuthRepository(apiClient: h.api, secureStorage: h.storage);
  }

  tearDown(() {
    current?.dispose();
    current = null;
  });

  group('DB-H2 session preservation', () {
    test('an existing session keeps working: the header is the token claim, not a new identifier', () async {
      setup(storage: {'jwt_access_token': testJwt(legacy), 'app_device_id': legacy});
      h.backend.routes[ApiEndpoints.balance] = (r) => (200, ok({'balance': 1}));
      await h.api.get(ApiEndpoints.balance);
      final r = h.backend.to(ApiEndpoints.balance).single;
      expect(r.headers['X-Device-ID'], legacy);
      expect(r.headers['Authorization'], 'Bearer ${testJwt(legacy)}');
      expect(await const FlutterSecureStorage().read(key: 'app_device_id'), legacy, reason: 'legacy value untouched');
      expect(h.unauthorized, 0);
    });

    test('pre-login requests use the canonical identifier and no stale token', () async {
      setup(storage: {'jwt_access_token': testJwt(legacy)});
      h.backend.routes[ApiEndpoints.termsAcceptances] = (r) => (201, ok({'acceptance_id': 'x'}));
      await h.api.post(ApiEndpoints.termsAcceptances, data: {});
      final r = h.backend.requests.single;
      expect(r.headers['X-Device-ID'], andId);
      expect(r.headers.containsKey('Authorization'), isFalse);
    });

    test('legacy binding: new identifier → 403/08 → recovery through OTP (no hint is sent)', () async {
      setup(storage: {'app_device_id': legacy});
      h.backend.routes[ApiEndpoints.login] = (r) => (403, apiFail('08', 'perangkat baru terdeteksi'));
      await expectLater(repo.login(identifier: '0812', password: 'x'), throwsA(isA<ApiException>().having((e) => e.responseCode, 'code', '08')));
      final body = h.backend.to(ApiEndpoints.login).single.body as Map;
      expect(body['device_id'], andId);
      expect(body.containsKey('legacy_device_id'), isFalse);
    });
  });

  group('DB-H1 no silent fallback', () {
    test('locked Keychain: login fails explicitly and nothing is sent', () async {
      setup(ios: true);
      h.native.identityError = 'KEYCHAIN_LOCKED';
      await expectLater(repo.login(identifier: '0812', password: 'x'), throwsA(anything));
      expect(h.backend.requests, isEmpty);
    });

    test('L2: corrupt iOS identity is replaced only inside Lupa Password (OTP), never at login', () async {
      setup(ios: true);
      h.native.identityError = 'DEVICE_ID_CORRUPT';
      await expectLater(repo.login(identifier: '0812', password: 'x'), throwsA(anything));
      expect(h.native.count('resetCorruptDeviceIdentity'), 0, reason: 'no automatic replacement');
      h.backend.routes[ApiEndpoints.forgotPasswordRequest] = (r) => (200, ok({'session_id': 's'}));
      await repo.requestForgotPassword(phoneNumber: '0812');
      expect(h.native.count('resetCorruptDeviceIdentity'), 1);
      final r = h.backend.to(ApiEndpoints.forgotPasswordRequest).single;
      expect((r.body as Map)['device_id'], 'ios-00000000-0000-4000-8000-00000000c0de');
      expect(r.headers['X-Device-ID'], 'ios-00000000-0000-4000-8000-00000000c0de');
    });

    test('API request without identity is rejected before sending', () async {
      setup();
      h.native.identityError = 'DEVICE_ID_UNAVAILABLE';
      await expectLater(h.api.post(ApiEndpoints.forgotPasswordRequest, data: {}),
          throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiFailureKind.notSent)));
      expect(h.backend.requests, isEmpty);
    });
  });

  group('DB-H4 / DB-H5 enrollment', () {
    void loginRoutes({Map<String, dynamic>? enrollResponse, int enrollStatus = 200}) {
      h.backend.routes[ApiEndpoints.login] = (r) => (200, ok(authData(andId, tag: 'login', binding: allowed(andId))));
      h.backend.routes[ApiEndpoints.deviceSessionChallenge] = (r) => (200, challenge('ENROLL'));
      h.backend.routes[ApiEndpoints.deviceEnroll] = (r) => (enrollStatus, enrollResponse ?? ok(authData(andId, tag: 'enrolled', binding: enrolled(andId))));
    }

    test('enrollment is awaited inside login; requests issued meanwhile use the new session', () async {
      setup();
      final enrollGate = Completer<void>();
      loginRoutes();
      h.backend.routes[ApiEndpoints.deviceEnroll] = (r) async {
        await enrollGate.future;
        return (200, ok(authData(andId, tag: 'enrolled', binding: enrolled(andId))));
      };
      h.backend.routes[ApiEndpoints.balance] = (r) => (200, ok({'balance': 1}));

      final login = repo.login(identifier: '0812', password: 'x');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final home = h.api.get(ApiEndpoints.balance); // Home screen request during enrollment
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(h.backend.to(ApiEndpoints.balance), isEmpty, reason: 'waits for the session operation');
      enrollGate.complete();
      final auth = await login;
      await home;
      expect(auth.accessToken, testJwt(andId, tag: 'acc-enrolled'));
      expect(h.backend.to(ApiEndpoints.balance).single.headers['Authorization'], 'Bearer ${testJwt(andId, tag: 'acc-enrolled')}');
      expect(await h.storage.getAccessToken(), testJwt(andId, tag: 'acc-enrolled'));
      expect(await h.storage.getDeviceKeyKind(), keyKindES256);
      // Android: the challenge nonce is the Key Attestation challenge; the chain is sent.
      final body = h.backend.to(ApiEndpoints.deviceEnroll).single.body as Map;
      expect(body['attestation_format'], 'android-key');
      expect(body['attestation_chain'], ['leaf-nonce-1', 'root']);
      expect(body['device_id'], andId);
      expect(h.unauthorized, 0);
    });

    test('enrollment failure never fails a valid login (dual mode)', () async {
      setup();
      loginRoutes(enrollStatus: 403, enrollResponse: apiFail('13', 'attestation ditolak'));
      final auth = await repo.login(identifier: '0812', password: 'x');
      expect(auth.accessToken, testJwt(andId, tag: 'acc-login'));
      expect(await h.storage.getAccessToken(), testJwt(andId, tag: 'acc-login'));
      expect(await h.storage.getDeviceKeyKind(), isNull);
    });

    test('single-flight: concurrent triggers produce one enrollment', () async {
      setup();
      loginRoutes();
      final gate = Completer<void>();
      h.backend.routes[ApiEndpoints.deviceEnroll] = (r) async {
        await gate.future;
        return (200, ok(authData(andId, tag: 'enrolled', binding: enrolled(andId))));
      };
      final st = DeviceBindingStatusModel.fromJson(allowed(andId));
      Future<dynamic> post(String p, Map<String, dynamic> b) => h.api.postInsideAuthLock(p, b);
      final a = h.api.deviceBinding.enrollIfAllowed(st, post);
      final b = h.api.deviceBinding.enrollIfAllowed(st, post);
      gate.complete();
      await Future.wait([a, b]);
      expect(h.backend.to(ApiEndpoints.deviceEnroll).length, 1);
    });

    test('re-enrollment after reset always generates a fresh key (never reuses one)', () async {
      setup(storage: {'device_key_kind': keyKindES256, 'device_key_ref': 'old-fingerprint'});
      loginRoutes();
      await repo.login(identifier: '0812', password: 'x');
      expect(h.native.count('generateKey'), 1);
      final ref = await h.storage.getDeviceKeyRef();
      expect(ref, isNot('old-fingerprint'));
      expect(ref, sha256Hex('spki-1'));
    });

    test('a 401 for a replaced token does not end the new session', () async {
      setup(storage: {'jwt_access_token': testJwt(andId, tag: 'old')});
      var calls = 0;
      h.backend.routes[ApiEndpoints.balance] = (r) async {
        calls++;
        if (calls == 1) {
          // The session was replaced (e.g. enrollment) while this request was in flight.
          await const FlutterSecureStorage().write(key: 'jwt_access_token', value: testJwt(andId, tag: 'new'));
          return (401, apiFail('01', 'Sesi tidak lagi sesuai dengan kunci keamanan perangkat'));
        }
        return (200, ok({'balance': 1}));
      };
      await h.api.get(ApiEndpoints.balance);
      expect(calls, 2);
      expect(h.backend.requests.last.headers['Authorization'], 'Bearer ${testJwt(andId, tag: 'new')}');
      expect(await h.storage.getAccessToken(), testJwt(andId, tag: 'new'));
      expect(h.unauthorized, 0);
    });

    test('iOS 14+: App Attest is the binding key (attestation, then assertions)', () async {
      setup(ios: true);
      h.native.appAttestSupported = true;
      const iosId = 'ios-1b4e28ba-2fa1-41d2-883f-0016d3cca427';
      h.backend.routes[ApiEndpoints.login] = (r) => (200, ok(authData(iosId, tag: 'login', binding: allowed(iosId))));
      h.backend.routes[ApiEndpoints.deviceSessionChallenge] = (r) => (200, challenge('ENROLL'));
      h.backend.routes[ApiEndpoints.deviceEnroll] = (r) => (200, ok(authData(iosId, tag: 'enr', binding: enrolled(iosId))));
      await repo.login(identifier: '0812', password: 'x');
      final body = h.backend.to(ApiEndpoints.deviceEnroll).single.body as Map;
      expect(body['attestation_format'], 'apple-appattest');
      expect(body['app_attest_key_id'], 'kid-1');
      expect(body.containsKey('public_key'), isFalse);
      expect(h.native.count('generateKey'), 0, reason: 'no unattested SE key when App Attest exists');
      expect(await h.storage.getDeviceKeyKind(), keyKindAppAttest);

      // Next login: assertion instead of signature.
      h.backend.routes[ApiEndpoints.deviceChallenge] = (r) => (200, challenge('LOGIN', 2));
      h.backend.routes[ApiEndpoints.login] = (r) => (200, ok(authData(iosId, tag: 'login2', binding: enrolled(iosId))));
      await repo.login(identifier: '0812', password: 'x');
      final loginBody = h.backend.to(ApiEndpoints.login).last.body as Map;
      expect((loginBody['device_signature'] as String).startsWith('assert:'), isTrue);
      expect(h.native.count('sign'), 0);
    });
  });

  group('proofs (DB-H4, DB-M4)', () {
    test('enrolled installation signs LOGIN with the exact protocol message', () async {
      setup(storage: {'device_key_kind': keyKindES256, 'device_key_ref': 'fp'});
      h.backend.routes[ApiEndpoints.deviceChallenge] = (r) => (200, challenge('LOGIN', 3));
      h.backend.routes[ApiEndpoints.login] = (r) => (200, ok(authData(andId, binding: enrolled(andId))));
      await repo.login(identifier: '0812', password: 'x');
      final body = h.backend.to(ApiEndpoints.login).single.body as Map;
      expect(body['device_challenge_id'], '11111111-2222-4333-8444-555555555553');
      final signed = utf8.decode(base64Decode((body['device_signature'] as String).substring(4)));
      expect(signed, startsWith('DMB-DEVICE-BINDING-V1\nLOGIN\n11111111-2222-4333-8444-555555555553\nnonce-3\n$andId\n'));
    });

    test('code 10 without a usable key directs to Lupa Password', () async {
      setup();
      h.backend.routes[ApiEndpoints.login] = (r) => (403, apiFail('10', 'verifikasi kunci keamanan perangkat diperlukan'));
      await expectLater(repo.login(identifier: '0812', password: 'x'),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Lupa Password'))));
    });

    test('change PIN carries a CHANGE_PIN proof bound to the operation', () async {
      setup(storage: {'jwt_access_token': testJwt(andId), 'device_key_kind': keyKindES256, 'device_key_ref': 'fp'});
      h.backend.routes[ApiEndpoints.deviceSessionChallenge] = (r) => (200, challenge('CHANGE_PIN', 4));
      h.backend.routes[ApiEndpoints.changePin] = (r) => (200, ok({'updated': true}));
      await repo.changePin(oldPin: '123456', newPin: '739182');
      expect((h.backend.to(ApiEndpoints.deviceSessionChallenge).single.body as Map)['purpose'], 'CHANGE_PIN');
      final body = h.backend.to(ApiEndpoints.changePin).single.body as Map;
      final signed = utf8.decode(base64Decode((body['device_signature'] as String).substring(4)));
      expect(signed.split('\n')[1], 'CHANGE_PIN');
      expect(signed.split('\n').last, sha256HexText('operation=CHANGE_PIN'));
    });

    test('refresh after expiry signs REFRESH with the session identifier from the token', () async {
      setup(storage: {
        'jwt_access_token': testJwt(andId, tag: 'old'),
        'jwt_refresh_token': testJwt(andId, tag: 'r-old'),
        'device_key_kind': keyKindES256,
        'device_key_ref': 'fp',
      });
      var balanceCalls = 0;
      h.backend.routes[ApiEndpoints.balance] = (r) => (++balanceCalls == 1 ? (401, apiFail('01', 'expired')) : (200, ok({'b': 1})));
      h.backend.routes[ApiEndpoints.deviceChallenge] = (r) => (200, challenge('REFRESH', 5));
      h.backend.routes[ApiEndpoints.refresh] = (r) => (200, ok(authData(andId, tag: 'new', binding: enrolled(andId))));
      await h.api.get(ApiEndpoints.balance);
      final refresh = h.backend.to(ApiEndpoints.refresh).single;
      expect(refresh.headers['X-Device-ID'], andId);
      expect((refresh.body as Map)['device_challenge_id'], '11111111-2222-4333-8444-555555555555');
      expect(await h.storage.getAccessToken(), testJwt(andId, tag: 'acc-new'));
    });
  });

  test('DeviceBindingService.deviceIdFromToken is the single session identifier source', () {
    expect(DeviceBindingService.deviceIdFromToken(testJwt(legacy)), legacy);
  });
}

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();
String sha256HexText(String s) => sha256Hex(s);
