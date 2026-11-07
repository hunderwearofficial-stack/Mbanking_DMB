class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseCode;
  final dynamic errors;

  ApiException({
    required this.message,
    this.statusCode,
    this.responseCode,
    this.errors,
  });

  @override
  String toString() => message;
}

