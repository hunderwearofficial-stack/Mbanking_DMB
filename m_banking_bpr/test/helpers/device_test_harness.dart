import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/network/api_client.dart';
import 'package:m_banking_bpr/core/security/device_binding_service.dart';
import 'package:m_banking_bpr/core/security/device_identity_service.dart';
import 'package:m_banking_bpr/core/security/secure_storage_service.dart';

/// Unsigned test JWT carrying only the claims the app reads (`device_id`).
String testJwt(String deviceId, {String tag = 'a'}) {
  String enc(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc({'device_id': deviceId, 'jti': tag})}.sig';
}

class RecordedRequest {
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final dynamic body;
  RecordedRequest(this.method, this.path, this.headers, this.body);
}

typedef FakeHandler = FutureOr<(int, Map<String, dynamic>)> Function(RecordedRequest r);

/// In-process HTTP adapter: the real ApiClient (interceptors, refresh, 401 handling) runs
/// against scripted backend responses.
class FakeBackend implements HttpClientAdapter {
  final Map<String, FakeHandler> routes = {};
  final List<RecordedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final r = RecordedRequest(options.method, options.path, Map<String, dynamic>.from(options.headers), options.data);
    requests.add(r);
    final h = routes[options.path];
    final (status, json) = h == null ? (404, {'success': false, 'message': 'not found ${options.path}'}) : await h(r);
    return ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}

  List<RecordedRequest> to(String path) => requests.where((r) => r.path == path).toList();
}

Map<String, dynamic> ok(dynamic data) => {'success': true, 'response_code': '00', 'message': 'ok', 'data': data};
Map<String, dynamic> apiFail(String code, String message) => {'success': false, 'response_code': code, 'message': message};

Map<String, dynamic> authData(String deviceId, {String tag = 'a', Map<String, dynamic>? binding}) => {
      'access_token': testJwt(deviceId, tag: 'acc-$tag'),
      'refresh_token': testJwt(deviceId, tag: 'ref-$tag'),
      'token_type': 'Bearer',
      'expires_in': 900,
      'user': {'id': 'u1', 'cif': '001', 'full_name': 'Nasabah', 'phone_number': '0812', 'primary_account': '001010', 'device_id': deviceId},
      if (binding != null) 'device_binding': binding,
    };

/// Fake native device identity / key layer.
class FakeNative {
  static const channel = MethodChannel(DeviceIdentityService.channelName);
  final List<MethodCall> calls = [];
  String platform = 'android';
  String deviceId = 'and-0123456789abcdef';
  String? identityError; // e.g. KEYCHAIN_LOCKED
  bool appAttestSupported = false;
  int keyCounter = 0;
  String? keyError;
  bool keyExists = false;
  bool appAttestKeyStored = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'getDeviceIdentity':
          if (identityError != null) throw PlatformException(code: identityError!, message: identityError);
          return {'device_id': deviceId, 'platform': platform};
        case 'generateKey':
          if (keyError != null) throw PlatformException(code: keyError!, message: keyError);
          keyCounter++;
          return {
            'exists': true,
            'public_key': base64Encode(utf8.encode('spki-$keyCounter')),
            'security_level': 'STRONGBOX',
            'attestation_chain': ['leaf-${args['attestation_challenge']}', 'root'],
          };
        case 'sign':
          return 'sig:${args['message']}';
        case 'resetCorruptDeviceIdentity':
          identityError = null;
          deviceId = platform == 'ios' ? 'ios-00000000-0000-4000-8000-00000000c0de' : deviceId;
          return {'device_id': deviceId, 'platform': platform};
        case 'getKeyInfo':
          return keyExists ? {'exists': true, 'public_key': base64Encode(utf8.encode('spki-existing')), 'security_level': 'STRONGBOX'} : {'exists': false};
        case 'appAttestKeyInfo':
          return appAttestKeyStored ? {'exists': true, 'key_id': 'kid-stored'} : {'exists': false};
        case 'appAttestSupported':
          return appAttestSupported;
        case 'appAttestGenerateKey':
          keyCounter++;
          return {'key_id': 'kid-$keyCounter'};
        case 'appAttestAttest':
          return {'key_id': 'kid-$keyCounter', 'attestation_object': 'att:${args['message']}'};
        case 'appAttestAssert':
          return 'assert:${args['message']}';
        default:
          return null;
      }
    });
  }

  void uninstall() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);

  int count(String method) => calls.where((c) => c.method == method).length;
}

/// Secure storage that fails every operation (platform storage unavailable).
class BrokenSecureStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
          WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) =>
      throw PlatformException(code: 'storage');

  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions,
          LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) =>
      throw PlatformException(code: 'storage');

  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
          WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) =>
      throw PlatformException(code: 'storage');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw PlatformException(code: 'storage');
}

class Harness {
  final FakeBackend backend = FakeBackend();
  final FakeNative native = FakeNative();
  late final SecureStorageService storage;
  late final ApiClient api;
  int unauthorized = 0;

  Harness({Map<String, String> initialStorage = const {}, bool ios = false, FlutterSecureStorage? secureStorage}) {
    FlutterSecureStorage.setMockInitialValues(Map<String, String>.from(initialStorage));
    DeviceIdentityService.resetCacheForTest();
    native.platform = ios ? 'ios' : 'android';
    native.deviceId = ios ? 'ios-1b4e28ba-2fa1-41d2-883f-0016d3cca427' : 'and-0123456789abcdef';
    native.install();
    storage = SecureStorageService(storage: secureStorage, deviceIdentityService: DeviceIdentityService());
    api = ApiClient(
      secureStorage: storage,
      onUnauthorized: () => unauthorized++,
      deviceBinding: DeviceBindingService(storage: storage, isIOS: () => ios),
    );
    api.dio.httpClientAdapter = backend;
  }

  void dispose() => native.uninstall();
}
