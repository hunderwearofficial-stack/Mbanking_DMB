import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Certificate pinning (audit DMB-010 / MA-08).
///
/// A pin is the SHA-256 of the server's SubjectPublicKeyInfo (SPKI, preferred: it survives
/// certificate renewal with the same key) or of the whole leaf certificate (legacy). Pins
/// are given as 64 hex characters or base64 of 32 bytes, comma separated, and must include
/// a backup pin for the next key.
class SslPinningService {
  static const String _pinsDefine = String.fromEnvironment('API_CERT_PINS');

  static final List<String> pins = parsePins(_pinsDefine);

  static bool get isPinningConfigured => pins.isNotEmpty;

  static List<String> parsePins(String raw) {
    final out = <String>[];
    for (final p in raw.split(',')) {
      final v = p.trim();
      if (v.isEmpty) continue;
      final hex = v.replaceAll(':', '').toLowerCase();
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
        out.add(hex);
        continue;
      }
      try {
        final bytes = base64.decode(v);
        if (bytes.length == 32) {
          out.add(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
        }
      } catch (_) {
        // Not a valid pin: ignored (the release gate refuses a build without valid pins).
      }
    }
    return out;
  }

  static String fingerprint(List<int> der) => sha256.convert(der).toString();

  /// SHA-256 of the certificate's SubjectPublicKeyInfo, or null when the DER cannot be read.
  static String? spkiFingerprint(List<int> der) {
    final spki = extractSpki(Uint8List.fromList(der));
    return spki == null ? null : sha256.convert(spki).toString();
  }

  static bool validateCertificate(X509Certificate? cert, String host, int port) {
    if (!isPinningConfigured) {
      return true; // standard CA validation still applies
    }
    if (cert == null) {
      return false; // no TLS => refuse when pinning is required
    }
    return matches(cert.der, pins);
  }

  static bool matches(List<int> der, List<String> pinSet) {
    if (pinSet.contains(fingerprint(der))) return true;
    final spki = spkiFingerprint(der);
    return spki != null && pinSet.contains(spki);
  }

  /// Returns the DER encoding (tag, length and value) of tbsCertificate.subjectPublicKeyInfo.
  static Uint8List? extractSpki(Uint8List der) {
    try {
      final cert = _readTlv(der, 0);
      if (cert == null || cert.tag != 0x30) return null;
      final tbs = _readTlv(der, cert.valueStart);
      if (tbs == null || tbs.tag != 0x30) return null;
      var pos = tbs.valueStart;
      var field = _readTlv(der, pos);
      if (field != null && field.tag == 0xA0) {
        pos = field.end; // explicit [0] version
      }
      // serialNumber, signature, issuer, validity, subject, then subjectPublicKeyInfo.
      for (var i = 0; i < 5; i++) {
        field = _readTlv(der, pos);
        if (field == null) return null;
        pos = field.end;
      }
      final spki = _readTlv(der, pos);
      if (spki == null || spki.tag != 0x30 || spki.end > tbs.end) return null;
      return Uint8List.sublistView(der, spki.start, spki.end);
    } catch (_) {
      return null;
    }
  }

  static _Tlv? _readTlv(Uint8List b, int start) {
    if (start + 2 > b.length) return null;
    final tag = b[start];
    var lenByte = b[start + 1];
    var pos = start + 2;
    int length;
    if (lenByte < 0x80) {
      length = lenByte;
    } else {
      final n = lenByte & 0x7F;
      if (n == 0 || n > 4 || pos + n > b.length) return null;
      length = 0;
      for (var i = 0; i < n; i++) {
        length = (length << 8) | b[pos + i];
      }
      pos += n;
    }
    final end = pos + length;
    if (end > b.length) return null;
    return _Tlv(tag, start, pos, end);
  }
}

class _Tlv {
  final int tag;
  final int start;
  final int valueStart;
  final int end;

  const _Tlv(this.tag, this.start, this.valueStart, this.end);
}
