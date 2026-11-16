/// How a request failed — needed to decide whether a money-moving request may have
/// reached the server (audit DMB-015).
enum ApiFailureKind {
  /// The server answered with an error response.
  server,

  /// The request was NOT delivered (no connection / connect timeout / certificate).
  notSent,

  /// The request may have been delivered but no answer arrived (send/receive timeout,
  /// dropped connection). For a transfer the outcome is UNKNOWN.
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

  @override
  String toString() => message;
}
