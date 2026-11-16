/// Metadata of the Terms and Conditions version in force, as published by the bank
/// through the back office (GET /api/v1/terms/active). The PDF itself is downloaded
/// separately and checked against [pdfSha256].
class TermsDocument {
  final String versionId;
  final int versionNumber;
  final String? documentNumber;
  final DateTime? publishedAt;
  final DateTime? effectiveFrom;
  final String pdfSha256;
  final String pdfUrl;
  final String consentHeading;
  final String consentInstruction;
  final List<String> consentStatements;

  const TermsDocument({
    required this.versionId,
    required this.versionNumber,
    required this.documentNumber,
    required this.publishedAt,
    required this.effectiveFrom,
    required this.pdfSha256,
    required this.pdfUrl,
    required this.consentHeading,
    required this.consentInstruction,
    required this.consentStatements,
  });

  static final RegExp _sha = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Strict parsing: an incomplete or malformed answer is an error, never a default.
  factory TermsDocument.fromJson(Map<String, dynamic> json) {
    final id = json['version_id'];
    final number = json['version_number'];
    final sha = json['pdf_sha256'];
    final statements = json['consent_statements'];
    if (id is! String || !_uuid.hasMatch(id) || number is! num || number < 1 || sha is! String || !_sha.hasMatch(sha)) {
      throw const FormatException('Metadata Syarat dan Ketentuan tidak valid');
    }
    if (statements is! List || statements.isEmpty || statements.any((s) => s is! String || s.trim().isEmpty)) {
      throw const FormatException('Pernyataan persetujuan tidak valid');
    }
    DateTime? date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    final docNo = json['document_number'];
    return TermsDocument(
      versionId: id,
      versionNumber: number.toInt(),
      documentNumber: docNo is String && docNo.trim().isNotEmpty ? docNo.trim() : null,
      publishedAt: date(json['published_at']),
      effectiveFrom: date(json['effective_from']),
      pdfSha256: sha,
      pdfUrl: json['pdf_url'] is String ? json['pdf_url'] as String : '',
      consentHeading: (json['consent_heading'] as String?)?.trim() ?? '',
      consentInstruction: (json['consent_instruction'] as String?)?.trim() ?? '',
      consentStatements: statements.cast<String>(),
    );
  }
}
