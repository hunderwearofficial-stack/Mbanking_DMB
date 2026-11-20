import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
      }
    }
    return out;
  }

  static String fingerprint(List<int> der) => sha256.convert(der).toString();

  static bool validateCertificate(X509Certificate? cert, String host, int port) {
    if (!isPinningConfigured) {
      return true; // standard CA validation still applies
    }
    if (cert == null) {
      return false; // no TLS => refuse when pinning is required
    }
    return pins.contains(fingerprint(cert.der));
  }
}
