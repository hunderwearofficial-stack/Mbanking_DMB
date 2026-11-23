import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/constants/bank_contact.dart';
import 'package:m_banking_bpr/core/content/app_content.dart';
import 'package:m_banking_bpr/core/services/dynamic_config_service.dart';

void main() {
  tearDown(() => DynamicConfigService().applyContentForTest({'version': -1, 'items': <String, dynamic>{}}));

  test('nilai terbit diterapkan; nilai tidak valid tidak pernah diterapkan', () {
    expect(AppContent.text('onboarding.button_text'), 'Mulai Sekarang');
    DynamicConfigService().applyContentForTest({
      'version': 4,
      'items': {
        'onboarding.button_text': 'Ayo Mulai',
        'contact.call_center_display': '(0251) 000-1111',
        'login.title': '<script>x</script>', // markup → ditolak
        'app.logo': 'javascript:alert(1)', // bukan https / unggahan → ditolak
        'home.banner2_visible': 'false',
        'home.banner1_action': 'transfer', // aksi tidak dikenal → ditolak
        'login.background': '/admin/uploads/login_ab12.jpg',
        'splash.bg_color': '#0A3B66',
      },
    });
    expect(DynamicConfigService().contentVersion, 4);
    expect(AppContent.text('onboarding.button_text'), 'Ayo Mulai');
    expect(BankContact.callCenterDisplay, '(0251) 000-1111');
    expect(AppContent.text('login.title'), 'Selamat datang');
    expect(AppContent.imageUrl('app.logo'), isNull);
    expect(AppContent.flag('home.banner2_visible'), isFalse);
    expect(AppContent.text('home.banner1_action'), 'profil');
    expect(AppContent.imageUrl('login.background'), endsWith('/admin/uploads/login_ab12.jpg'));
    expect(AppContent.color('splash.bg_color', const Color(0xFF091324)), const Color(0xFF0A3B66));
  });

  testWidgets('versi konten baru tampil tanpa restart aplikasi', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ContentRefreshScope(child: child!),
      home: Scaffold(body: Builder(builder: (_) => Text(AppContent.text('login.title')))),
    ));
    expect(find.text('Selamat datang'), findsOneWidget);
    DynamicConfigService().applyContentForTest({
      'version': 7,
      'items': {'login.title': 'Halo Nasabah'},
    });
    await tester.pump();
    expect(find.text('Halo Nasabah'), findsOneWidget);
  });
}
