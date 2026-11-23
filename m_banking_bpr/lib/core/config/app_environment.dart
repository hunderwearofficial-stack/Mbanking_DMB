import 'package:flutter/foundation.dart';
import '../security/ssl_pinning_service.dart';

enum AppFlavor { local, development, staging, production }

class AppEnvironment {
  AppEnvironment._();

  static const String _flavorRaw = String.fromEnvironment('APP_FLAVOR');
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _certPins = String.fromEnvironment('API_CERT_PINS');

  static AppFlavor? get flavor => parseFlavor(_flavorRaw);

  static bool get isProduction => flavor == AppFlavor.production;

  static String get apiBaseUrl => _apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  static AppFlavor? parseFlavor(String raw) {
    for (final f in AppFlavor.values) {
      if (f.name == raw.trim().toLowerCase()) return f;
    }
    return null;
  }

  static String? validate() => validateValues(
        flavorRaw: _flavorRaw,
        apiBaseUrl: _apiBaseUrl,
        certPins: _certPins,
        isRelease: kReleaseMode,
      );

  static String? validateValues({
    required String flavorRaw,
    required String apiBaseUrl,
    required String certPins,
    required bool isRelease,
    bool strictPinFormat = false,
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
        if (flavor == AppFlavor.production && isRelease) {
          final tokens = certPins.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          if (tokens.isEmpty || (strictPinFormat && SslPinningService.parsePins(certPins).isEmpty)) {
            return 'Build rilis production wajib menyertakan API_CERT_PINS (pin sertifikat aktif dan cadangan).';
          }
        }
        return null;
    }
  }
}
