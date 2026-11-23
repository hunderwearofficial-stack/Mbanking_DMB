import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/security/ssl_pinning_service.dart';

// Throwaway self-signed certificate (CN=pin-test.invalid, private key discarded). The
// expected hashes were computed independently with OpenSSL:
//   openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256
const _certB64 =
    'MIIBijCCATGgAwIBAgIUelqHf1Ral2bm0Eg3uOW8emaU15kwCgYIKoZIzj0EAwIwGzEZMBcGA1UEAwwQcGluLXRlc3QuaW52YWxpZDAeFw0yNjExMjAwNjU2NDBaFw0yNjExMjEwNjU2NDBaMBsxGTAXBgNVBAMMEHBpbi10ZXN0LmludmFsaWQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATIKSKKH36ItsddQi+g8e0iwBvwiC3/dimjeVdT2gecuoTo3yXz2BSkabt3LcjhmjwnGpg/HnMcEkU5INxClTe3o1MwUTAdBgNVHQ4EFgQU6yZAbR04qjWD+cGzj17Vm6scfy4wHwYDVR0jBBgwFoAU6yZAbR04qjWD+cGzj17Vm6scfy4wDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBEAiEA+QQTKUwXcWvgNotOXL50jvCJ+y6PwnjKfI5UrpPBMIwCHzDs+MIGAxNG+alycS2NT0MUP2LCgWRnPhudHlCLt6E=';
const _spkiSha256 = '14e2500d68167a8b6ad1442f9c96529ccbd07fdc8b0328df969f0b9d91e2a3e3';
const _certSha256 = 'd2672eee736e5b34976a61cd5b799f2d611bc0af3a1cd06ad4889087feb1fdcb';

void main() {
  final der = base64.decode(_certB64);

  test('SPKI hash matches OpenSSL', () {
    expect(SslPinningService.spkiFingerprint(der), _spkiSha256);
    expect(SslPinningService.fingerprint(der), _certSha256);
  });

  test('SPKI pin (hex or base64) and legacy certificate pin are accepted', () {
    final spkiB64 = base64.encode(List<int>.generate(32, (i) => int.parse(_spkiSha256.substring(i * 2, i * 2 + 2), radix: 16)));
    expect(SslPinningService.matches(der, SslPinningService.parsePins(_spkiSha256)), isTrue);
    expect(SslPinningService.matches(der, SslPinningService.parsePins(spkiB64)), isTrue);
    expect(SslPinningService.matches(der, SslPinningService.parsePins(_certSha256)), isTrue);
  });

  test('a different key is refused', () {
    final other = 'ab' * 32;
    expect(SslPinningService.matches(der, SslPinningService.parsePins(other)), isFalse);
  });

  test('malformed DER yields no SPKI and is not pinned', () {
    expect(SslPinningService.extractSpki(Uint8List.fromList([0x30, 0x82, 0xff])), isNull);
    expect(SslPinningService.matches(const [1, 2, 3], SslPinningService.parsePins(_spkiSha256)), isFalse);
  });
}
