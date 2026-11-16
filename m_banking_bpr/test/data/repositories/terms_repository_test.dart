import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/constants/api_endpoints.dart';
import 'package:m_banking_bpr/core/network/api_exception.dart';
import 'package:m_banking_bpr/core/services/terms_consent_store.dart';
import 'package:m_banking_bpr/data/models/terms_document.dart';
import 'package:m_banking_bpr/data/repositories/terms_repository.dart';

import '../../helpers/fake_api_client.dart';

final Uint8List samplePdf = Uint8List.fromList(utf8.encode('%PDF-1.4\n% contoh dokumen uji\n%%EOF'));
final String sampleSha = sha256.convert(samplePdf).toString();

Map<String, dynamic> activeJson({String? sha, List<dynamic>? statements}) => {
      'version_id': '8f14e45f-ceea-467a-9575-8d1e6b0f3c2a',
      'version_number': 3,
      'document_number': null,
      'published_at': '2026-11-14T03:00:00Z',
      'effective_from': '2026-11-15T00:00:00+07:00',
      'pdf_sha256': sha ?? sampleSha,
      'pdf_url': '/api/v1/terms/versions/8f14e45f-ceea-467a-9575-8d1e6b0f3c2a/pdf',
      'consent_heading': 'Persetujuan Layanan Nasabah',
      'consent_instruction': 'Silakan centang:',
      'consent_statements': statements ?? ['Satu', 'Dua', 'Tiga'],
    };

class BytesApiClient extends ScriptedApiClient {
  Uint8List bytes;
  int downloads = 0;
  BytesApiClient(this.bytes, {super.getResult, super.postResult, super.postError});

  @override
  Future<Uint8List> getBytes(String path) async {
    downloads++;
    return bytes;
  }
}

void main() {
  setUp(() {
    TermsRepository.clearCache();
    TermsConsentStore.instance.clear();
  });

  test('metadata SK diparsing ketat (tanpa nilai bawaan)', () async {
    final doc = await TermsRepository(apiClient: ScriptedApiClient(getResult: activeJson())).fetchActive();
    expect(doc.versionNumber, 3);
    expect(doc.consentStatements, ['Satu', 'Dua', 'Tiga']);
    expect(doc.documentNumber, isNull);
    for (final bad in [
      activeJson(sha: 'bukan-hash'),
      activeJson(statements: []),
      {...activeJson(), 'version_id': '../../etc'},
      {...activeJson(), 'version_number': 0},
    ]) {
      expect(() => TermsDocument.fromJson(bad), throwsFormatException);
      await expectLater(TermsRepository(apiClient: ScriptedApiClient(getResult: bad)).fetchActive(), throwsA(isA<ApiException>()));
    }
  });

  test('PDF diverifikasi dengan SHA-256 versi terbit dan di-cache per versi', () async {
    final api = BytesApiClient(samplePdf, getResult: activeJson());
    final repo = TermsRepository(apiClient: api);
    final doc = await repo.fetchActive();
    expect(await repo.fetchPdf(doc), samplePdf);
    await repo.fetchPdf(doc);
    expect(api.downloads, 1, reason: 'versi yang sama tidak diunduh berulang');

    TermsRepository.clearCache();
    api.bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 dokumen lain %%EOF'));
    await expectLater(repo.fetchPdf(doc), throwsA(isA<TermsIntegrityException>()));
    api.bytes = Uint8List.fromList(utf8.encode('<html>bukan pdf</html>'));
    await expectLater(repo.fetchPdf(doc), throwsA(isA<TermsIntegrityException>()));
  });

  test('persetujuan hanya dianggap berhasil setelah backend mengonfirmasi', () async {
    final doc = TermsDocument.fromJson(activeJson());
    final ok = ScriptedApiClient(postResult: {'acceptance_id': 'acc-1', 'version_id': doc.versionId, 'version_number': 3});
    expect(await TermsRepository(apiClient: ok).accept(doc), 'acc-1');
    expect(ok.lastBody, {'version_id': doc.versionId, 'accepted': true});
    expect(TermsConsentStore.instance.acceptanceId, 'acc-1');

    TermsConsentStore.instance.clear();
    final failing = ScriptedApiClient(postError: ApiException(message: 'Layanan sedang tidak tersedia', statusCode: 503));
    await expectLater(TermsRepository(apiClient: failing).accept(doc), throwsA(isA<ApiException>()));
    expect(TermsConsentStore.instance.acceptanceId, isNull);

    final wrongVersion = ScriptedApiClient(postResult: {'acceptance_id': 'acc-2', 'version_id': 'lain'});
    await expectLater(TermsRepository(apiClient: wrongVersion).accept(doc), throwsA(isA<ApiException>()));
    expect(TermsConsentStore.instance.acceptanceId, isNull);
  });

  test('endpoint SK sesuai backend', () {
    expect(ApiEndpoints.termsActive, '/api/v1/terms/active');
    expect(ApiEndpoints.termsAcceptances, '/api/v1/terms/acceptances');
    expect(ApiEndpoints.termsPdf('abc'), '/api/v1/terms/versions/abc/pdf');
  });
}
