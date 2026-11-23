import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/security/ssl_pinning_service.dart';

/// Certificate pinning (audit DMB-010).
void main() {
  final der = utf8.encode('example-der-bytes');
  final hex = sha256.convert(der).toString();

  test('fingerprint is a real SHA-256 of the DER bytes', () {
    expect(SslPinningService.fingerprint(der), hex);
    expect(hex.length, 64);
  });

  test('pins accept hex with colons and base64, ignore garbage', () {
    final colon = RegExp(r'..').allMatches(hex).map((m) => m.group(0)).join(':').toUpperCase();
    final b64 = base64.encode(sha256.convert(der).bytes);
    final pins = SslPinningService.parsePins('$colon, $b64, not-a-pin, ');
    expect(pins, [hex, hex]);
  });

  test('no pins configured by default => standard CA validation only', () {
    expect(SslPinningService.isPinningConfigured, isFalse);
    expect(SslPinningService.validateCertificate(null, 'example.com', 443), isTrue);
  });
}
