enum ApiFailureKind {
  server,

  notSent,

  outcomeUnknown,
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseCode;
  final dynamic errors;
  final ApiFailureKind kind;

  ApiException({
    required this.message,
    this.statusCode,
    this.responseCode,
    this.errors,
    this.kind = ApiFailureKind.server,
  });

  static const String defaultFallback =
      'Layanan sedang tidak dapat memproses permintaan Anda. Silakan coba kembali beberapa saat lagi.';

  /// Converts any [error] into a clean, customer-friendly Indonesian message
  /// without leaking technical terms (CBS, Core Banking, Server, API, Database,
  /// Exception, DioException, FragmentActivity, etc.).
  static String humanize(
    Object? error, {
    String fallback = defaultFallback,
  }) {
    if (error == null) return fallback;
    if (error is ApiException) {
      return sanitizeText(error.message, fallback: fallback);
    }
    final raw = error.toString().trim();
    if (raw.isEmpty) return fallback;
    return sanitizeText(raw, fallback: fallback);
  }

  static String sanitizeText(
    String raw, {
    String fallback = defaultFallback,
  }) {
    var msg = raw
        .replaceFirst(RegExp(r'^(Exception|ApiException|DioException|FormatException|RangeError|StateError):\s*', caseSensitive: false), '')
        .trim();
    if (msg.isEmpty) return fallback;

    final lower = msg.toLowerCase();
    if (lower.contains('dioexception') ||
        lower.contains('formatexception') ||
        lower.contains('rangeerror') ||
        lower.contains('typeerror') ||
        lower.contains('null check operator') ||
        lower.contains('socketexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('fragmentactivity') ||
        lower.contains('sqlstate') ||
        lower.contains('database') ||
        lower.contains('stacktrace')) {
      return fallback;
    }

    // Replace technical terms with polite banking terminology
    msg = msg
        .replaceAll(RegExp(r'\bCore Banking(\s+System)?\b', caseSensitive: false), 'sistem perbankan')
        .replaceAll(RegExp(r'\bCBS\b'), 'sistem perbankan')
        .replaceAll(RegExp(r'\bserver\s+Bank\s+DMB\b', caseSensitive: false), 'layanan Bank DMB')
        .replaceAll(RegExp(r'\bserver\b', caseSensitive: false), 'layanan')
        .replaceAll(RegExp(r'\bAPI\b'), 'layanan')
        .replaceAll(RegExp(r'\bbackend\b', caseSensitive: false), 'layanan');

    return msg;
  }

  @override
  String toString() => message;
}
