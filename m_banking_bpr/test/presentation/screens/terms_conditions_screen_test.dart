import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/network/api_exception.dart';
import 'package:m_banking_bpr/data/models/terms_document.dart';
import 'package:m_banking_bpr/data/repositories/terms_repository.dart';
import 'package:m_banking_bpr/presentation/screens/auth/terms_conditions_screen.dart';

import '../../data/repositories/terms_repository_test.dart' show activeJson, samplePdf;
import '../../helpers/fake_api_client.dart';

/// Repository double: scripted metadata/PDF/accept outcomes.
class FakeTermsRepository extends TermsRepository {
  Object? fetchError;
  Object? acceptError;
  int acceptCalls = 0;
  FakeTermsRepository() : super(apiClient: ScriptedApiClient());

  @override
  Future<TermsDocument> fetchActive() async {
    if (fetchError != null) throw fetchError!;
    return TermsDocument.fromJson(activeJson());
  }

  @override
  Future<Uint8List> fetchPdf(TermsDocument doc) async => samplePdf;

  @override
  Future<String> accept(TermsDocument doc) async {
    acceptCalls++;
    if (acceptError != null) throw acceptError!;
    return 'acc-1';
  }
}

/// PDF viewer double: reports the page count on demand (or a corrupt document).
class FakePdf {
  void Function(int)? loaded;
  void Function(Object)? error;
  Widget build(Uint8List bytes, void Function(int) onLoaded, void Function(Object) onError, void Function(int) onPage) {
    loaded = onLoaded;
    error = onError;
    return const ColoredBox(key: Key('fakePdf'), color: Color(0xFFFFFFFF));
  }
}

Future<void> pump(WidgetTester tester, FakeTermsRepository repo, FakePdf pdf, {VoidCallback? onAccepted}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: TermsConditionsScreen(repository: repo, pdfViewBuilder: pdf.build, onAccepted: onAccepted ?? () {}),
  ));
  await tester.pumpAndSettle();
}

ElevatedButton proceed(WidgetTester tester) => tester.widget<ElevatedButton>(find.byKey(const Key('termsProceedButton')));

Future<void> checkAll(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.ensureVisible(find.byKey(Key('termsConsent$i')));
    await tester.tap(find.byKey(Key('termsConsent$i')));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('tombol setuju aktif hanya bila PDF tampil, versi valid, dan semua kotak dicentang', (tester) async {
    final repo = FakeTermsRepository();
    final pdf = FakePdf();
    var accepted = false;
    await pump(tester, repo, pdf, onAccepted: () => accepted = true);

    expect(find.byKey(const Key('fakePdf')), findsOneWidget);
    expect(find.textContaining('Versi 3'), findsWidgets);
    expect(find.text('Satu'), findsOneWidget); // statements come from the published version
    expect(proceed(tester).onPressed, isNull);

    // Before the PDF is rendered, consent can not be given.
    await checkAll(tester);
    expect(proceed(tester).onPressed, isNull);

    pdf.loaded!(3);
    await tester.pumpAndSettle();
    expect(find.text('Halaman 1 dari 3'), findsOneWidget);
    await checkAll(tester);
    expect(proceed(tester).onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('termsProceedButton')));
    await tester.tap(find.byKey(const Key('termsProceedButton')));
    await tester.pumpAndSettle();
    expect(repo.acceptCalls, 1);
    expect(accepted, isTrue);
  });

  testWidgets('kegagalan pencatatan persetujuan tidak melanjutkan alur', (tester) async {
    final repo = FakeTermsRepository()..acceptError = ApiException(message: 'Layanan sedang tidak tersedia, silakan coba beberapa saat lagi', statusCode: 503);
    final pdf = FakePdf();
    var accepted = false;
    await pump(tester, repo, pdf, onAccepted: () => accepted = true);
    pdf.loaded!(2);
    await tester.pumpAndSettle();
    await checkAll(tester);
    await tester.ensureVisible(find.byKey(const Key('termsProceedButton')));
    await tester.tap(find.byKey(const Key('termsProceedButton')));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
    expect(find.text('Layanan sedang tidak tersedia, silakan coba beberapa saat lagi'), findsOneWidget);
    expect(proceed(tester).onPressed, isNotNull, reason: 'pengguna dapat mencoba lagi');
  });

  testWidgets('gangguan jaringan dan PDF rusak ditampilkan dengan opsi coba lagi', (tester) async {
    final repo = FakeTermsRepository()..fetchError = ApiException(message: 'Tidak dapat terhubung ke server Bank DMB.');
    final pdf = FakePdf();
    await pump(tester, repo, pdf);
    expect(find.byKey(const Key('termsError')), findsOneWidget);
    expect(find.text('Tidak dapat terhubung ke server Bank DMB.'), findsOneWidget);
    expect(proceed(tester).onPressed, isNull);

    repo.fetchError = null;
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fakePdf')), findsOneWidget);

    pdf.error!(Exception('corrupt'));
    await tester.pumpAndSettle();
    expect(find.text('Dokumen PDF tidak dapat ditampilkan. Silakan muat ulang.'), findsOneWidget);
    expect(proceed(tester).onPressed, isNull);
  });

  testWidgets('dokumen yang tidak sesuai hash tidak ditampilkan', (tester) async {
    final repo = FakeTermsRepository()..fetchError = const TermsIntegrityException('Dokumen yang diterima tidak sesuai dengan versi yang diterbitkan bank. Silakan muat ulang.');
    await pump(tester, repo, FakePdf());
    expect(find.byKey(const Key('fakePdf')), findsNothing);
    expect(find.textContaining('tidak sesuai dengan versi'), findsOneWidget);
  });
}
