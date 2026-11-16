import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Certificate pinning for the banking API (audit DMB-010).
///
/// The previous implementation used `badCertificateCallback`, which is only
/// invoked for certificates that FAILED validation and therefore *accepted*
/// invalid certificates; its "SHA-256" was not a hash. This version:
///   * never overrides the platform's normal TLS/CA validation;
///   * additionally (when pins are configured) requires the SHA-256 of the
///     server's leaf certificate (DER) to match one of the pins.
///
/// Pins are injected at build time (comma separated, hex with or without
/// colons, or base64):
///   --dart-define=API_CERT_PINS=<current-cert-sha256>,<backup-cert-sha256>
/// Always ship at least one backup pin and rotate certificates only after an app
/// update containing the new pin. Pinning complements — never replaces — server-side
/// authorization; it does not protect a rooted/instrumented device.
class SslPinningService {
  static const String _pinsDefine = String.fromEnvironment('API_CERT_PINS');

  static final List<String> pins = parsePins(_pinsDefine);

  static bool get isPinningConfigured => pins.isNotEmpty;

  /// Normalizes a comma-separated pin list (hex with/without colons, or base64) to lowercase hex.
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
        // ignore malformed pin
      }
    }
    return out;
  }

  /// SHA-256 (hex) of a DER-encoded certificate.
  static String fingerprint(List<int> der) => sha256.convert(der).toString();

  /// Used as dio's `IOHttpClientAdapter.validateCertificate`, which runs AFTER the
  /// platform has already validated the certificate chain.
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
