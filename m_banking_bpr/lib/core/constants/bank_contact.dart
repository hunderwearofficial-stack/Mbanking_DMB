import 'package:flutter/services.dart';

import '../content/app_content.dart';

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

  static void callCenter() {
    Clipboard.setData(ClipboardData(text: callCenterDial));
  }

  static void chatWhatsApp() {
    Clipboard.setData(ClipboardData(text: whatsAppDial));
  }
}
