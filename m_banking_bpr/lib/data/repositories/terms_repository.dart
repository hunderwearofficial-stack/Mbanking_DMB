import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/terms_consent_store.dart';
import '../models/terms_document.dart';

class TermsIntegrityException implements Exception {
  final String message;
  const TermsIntegrityException(this.message);
  @override
  String toString() => message;
}

class TermsRepository {
  final ApiClient apiClient;
  final TermsConsentStore consentStore;

  TermsRepository({required this.apiClient, TermsConsentStore? consentStore})
      : consentStore = consentStore ?? TermsConsentStore.instance;

  static String? _cachedKey;
  static Uint8List? _cachedPdf;

  static void clearCache() {
    _cachedKey = null;
    _cachedPdf = null;
  }

  Future<TermsDocument> fetchActive() async {
    final res = await apiClient.get(ApiEndpoints.termsActive);
    if (res is! Map<String, dynamic>) {
      throw ApiException(message: 'Syarat dan Ketentuan belum dapat dimuat. Silakan coba kembali.');
    }
    try {
      return TermsDocument.fromJson(res);
    } on FormatException {
      throw ApiException(message: 'Syarat dan Ketentuan belum dapat dimuat. Silakan coba kembali.');
    }
  }

  Future<Uint8List> fetchPdf(TermsDocument doc) async {
    final key = '${doc.versionId}:${doc.pdfSha256}';
    if (_cachedKey == key && _cachedPdf != null) return _cachedPdf!;
    final bytes = await apiClient.getBytes(ApiEndpoints.termsPdf(doc.versionId));
    verifyPdf(bytes, doc.pdfSha256);
    _cachedKey = key;
    _cachedPdf = bytes;
    return bytes;
  }

  static void verifyPdf(Uint8List bytes, String expectedSha256) {
    final isPdf = bytes.length > 5 && String.fromCharCodes(bytes.sublist(0, 5)) == '%PDF-';
    if (!isPdf || sha256.convert(bytes).toString() != expectedSha256) {
      throw const TermsIntegrityException('Dokumen yang diterima tidak sesuai dengan versi yang diterbitkan bank. Silakan muat ulang.');
    }
  }

  Future<String> accept(TermsDocument doc) async {
    final res = await apiClient.post(ApiEndpoints.termsAcceptances, data: {
      'version_id': doc.versionId,
      'accepted': true,
    });
    final id = res is Map<String, dynamic> ? res['acceptance_id'] : null;
    final version = res is Map<String, dynamic> ? res['version_id'] : null;
    if (id is! String || id.isEmpty || version != doc.versionId) {
      throw ApiException(message: 'Persetujuan belum dapat dicatat. Silakan coba kembali.');
    }
    consentStore.record(acceptanceId: id, versionId: doc.versionId);
    return id;
  }
}
