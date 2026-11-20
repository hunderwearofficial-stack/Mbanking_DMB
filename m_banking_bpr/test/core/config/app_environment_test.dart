import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/config/app_environment.dart';

String? check(String flavor, String url, {String pins = '', bool release = false}) =>
    AppEnvironment.validateValues(flavorRaw: flavor, apiBaseUrl: url, certPins: pins, isRelease: release);

void main() {
  test('local debug over HTTP to the Windows LAN IP is allowed', () {
    expect(check('local', 'http://192.168.1.20:8080'), isNull);
  });

  test('no default: missing flavor or URL is an error', () {
    expect(check('', 'http://192.168.1.20:8080'), contains('APP_FLAVOR'));
    expect(check('prod', 'https://api.example.invalid'), contains('APP_FLAVOR'));
    expect(check('local', ''), contains('API_BASE_URL'));
    expect(check('local', 'not a url'), isNotNull);
  });

  test('physical phone cannot use localhost', () {
    expect(check('local', 'http://localhost:8080'), contains('IP server/VPS'));
    expect(check('local', 'http://127.0.0.1:8080'), contains('IP server/VPS'));
  });

  test('local and development allow release testing over HTTP', () {
    expect(check('local', 'http://192.168.1.20:8080', release: true), isNull);
    expect(check('development', 'http://103.93.134.64:8080', release: true), isNull);
  });

  test('staging and production require HTTPS', () {
    for (final f in ['staging', 'production']) {
      expect(check(f, 'http://192.168.1.20:8080'), contains('HTTPS'), reason: f);
      expect(check(f, 'https://api-$f.example.invalid'), isNull, reason: f);
    }
  });

  test('production never points to a private address and release needs pins', () {
    expect(check('production', 'https://192.168.1.20'), contains('lokal/privat'));
    expect(check('production', 'https://api.example.invalid', release: true), contains('API_CERT_PINS'));
    expect(check('production', 'https://api.example.invalid', pins: 'aa,bb', release: true), isNull);
  });
}
