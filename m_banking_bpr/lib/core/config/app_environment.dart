import 'package:flutter/foundation.dart';

/// Environment aplikasi mobile (flavor), ditentukan SAAT BUILD:
///
///   flutter run   --dart-define-from-file=config/local.json --dart-define=API_BASE_URL=http://<IP-LAN>:8080
///   flutter build apk --release --dart-define-from-file=config/production.json
///
/// Tidak ada nilai default: bila APP_FLAVOR / API_BASE_URL tidak valid, aplikasi
/// menampilkan layar kesalahan konfigurasi (tidak diam-diam memakai alamat lain).
/// Aplikasi mobile TIDAK PERNAH menyimpan secret backend (DB, JWT, kunci enkripsi).
enum AppFlavor { local, development, staging, production }

class AppEnvironment {
  AppEnvironment._();

  static const String _flavorRaw = String.fromEnvironment('APP_FLAVOR');
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _certPins = String.fromEnvironment('API_CERT_PINS');

  /// The configured flavor, or null when APP_FLAVOR is missing/unknown.
  static AppFlavor? get flavor => parseFlavor(_flavorRaw);

  static String get apiBaseUrl => _apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  static AppFlavor? parseFlavor(String raw) {
    for (final f in AppFlavor.values) {
      if (f.name == raw.trim().toLowerCase()) return f;
    }
    return null;
  }

  /// Validation error for the compiled configuration, or null when valid.
  static String? validate() => validateValues(
        flavorRaw: _flavorRaw,
        apiBaseUrl: _apiBaseUrl,
        certPins: _certPins,
        isRelease: kReleaseMode,
      );

  /// Pure validation (unit-tested).
  static String? validateValues({
    required String flavorRaw,
    required String apiBaseUrl,
    required String certPins,
    required bool isRelease,
  }) {
    final flavor = parseFlavor(flavorRaw);
    if (flavor == null) {
      return 'APP_FLAVOR tidak valid ("$flavorRaw"). Gunakan local, development, staging, atau production '
          '(build dengan --dart-define-from-file=config/<flavor>.json).';
    }
    final url = apiBaseUrl.trim();
    if (url.isEmpty) {
      return 'API_BASE_URL belum diisi untuk flavor ${flavor.name}.';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'API_BASE_URL tidak valid: $url (contoh: http://192.168.1.20:8080 untuk local).';
    }
    final host = uri.host.toLowerCase();
    final isLoopback = host == 'localhost' || host == '127.0.0.1' || host == '::1';
    final isPrivate = isLoopback ||
        RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)').hasMatch(host);

    switch (flavor) {
      case AppFlavor.local:
      case AppFlavor.development:
        if (isLoopback) {
          return 'API_BASE_URL local tidak boleh localhost/127.0.0.1: HP fisik harus memakai IP server/VPS '
              '(mis. http://103.93.134.64:8080).';
        }
        return null;
      case AppFlavor.staging:
      case AppFlavor.production:
        if (uri.scheme != 'https') {
          return 'Flavor ${flavor.name} wajib memakai HTTPS (API_BASE_URL=$url).';
        }
        if (flavor == AppFlavor.production && isPrivate) {
          return 'Flavor production tidak boleh mengarah ke alamat lokal/privat ($host).';
        }
        if (flavor == AppFlavor.production && isRelease && certPins.trim().isEmpty) {
          return 'Build rilis production wajib menyertakan API_CERT_PINS (pin sertifikat aktif dan cadangan).';
        }
        return null;
    }
  }
}
