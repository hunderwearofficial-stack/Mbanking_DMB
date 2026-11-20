import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/content/app_content.dart';
import 'package:m_banking_bpr/core/network/api_client.dart';
import 'package:m_banking_bpr/core/security/secure_storage_service.dart';
import 'package:m_banking_bpr/core/services/dynamic_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end against a running backend (not part of the regular suite): the app's own
/// ApiClient + DynamicConfigService download the published content and the widget shows
/// the new value without restarting. Run with
///   flutter test test/core/content/live_content_e2e_test.dart \
///     --dart-define=APP_FLAVOR=local --dart-define=API_BASE_URL=http://<host>:<port> \
///     --dart-define=E2E_EXPECT_TITLE=<published onboarding.slide1_title>
const _expected = String.fromEnvironment('E2E_EXPECT_TITLE');

void main() {
  testWidgets('aplikasi mengambil versi konten terbit dari server dan layar berubah', (tester) async {
    if (_expected.isEmpty) {
      markTestSkipped('E2E_EXPECT_TITLE tidak diisi');
      return;
    }
    HttpOverrides.global = null; // real network for this test only
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ContentRefreshScope(child: child!),
      home: Scaffold(body: Builder(builder: (_) => Text(AppContent.text('onboarding.slide1_title')))),
    ));
    expect(find.text('Solusi Finansial Terpercaya untuk Keluarga & UMKM'), findsOneWidget,
        reason: 'sebelum unduhan: nilai bawaan aplikasi');

    final ok = await tester.runAsync(() => DynamicConfigService()
        .refreshContent(apiClient: ApiClient(secureStorage: SecureStorageService())));
    expect(ok, isTrue, reason: 'GET /api/v1/content harus berhasil');
    expect(DynamicConfigService().contentVersion, greaterThan(0));
    await tester.pump();
    expect(find.text(_expected), findsOneWidget, reason: 'layar harus menampilkan konten yang dipublikasikan');
  });
}
