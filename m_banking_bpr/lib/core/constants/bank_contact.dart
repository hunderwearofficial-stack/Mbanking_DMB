import 'package:flutter/services.dart';

import '../content/app_content.dart';

/// Kontak layanan nasabah Bank DMB — satu-satunya sumber di aplikasi.
///
/// Nilai dikelola bank melalui Backoffice (Konten Aplikasi → Kontak Layanan,
/// GET /api/v1/content). Nilai bawaan (sebelum unduhan pertama) adalah nilai yang
/// sebelumnya ditanam di aplikasi dan BELUM diverifikasi bank (lihat
/// docs/USER_MANUAL.md bagian 13) — bank wajib menerbitkan kontak resmi.
class BankContact {
  BankContact._();

  static String get callCenterDisplay => AppContent.text('contact.call_center_display');
  static String get callCenterDial => AppContent.text('contact.call_center_dial');

  static String get whatsAppDisplay => AppContent.text('contact.whatsapp_display');
  static String get whatsAppDial => AppContent.text('contact.whatsapp_dial');

  static String get email => AppContent.text('contact.email');

  static String get headOfficeShort => AppContent.text('contact.office_short');
  static String get headOfficeAddress => AppContent.text('contact.office_address');

  static String get officeHours => AppContent.text('contact.office_hours');

  /// Salin nomor call center ke clipboard
  static void callCenter() {
    Clipboard.setData(ClipboardData(text: callCenterDial));
  }

  /// Salin nomor WhatsApp ke clipboard
  static void chatWhatsApp() {
    Clipboard.setData(ClipboardData(text: whatsAppDial));
  }
}
