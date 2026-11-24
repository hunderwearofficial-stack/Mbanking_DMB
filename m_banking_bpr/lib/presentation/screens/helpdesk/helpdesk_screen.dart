import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/bank_contact.dart';
import '../../../core/content/app_content.dart';
import '../../widgets/auth_ui_kit.dart';

class HelpdeskScreen extends StatelessWidget {
  final bool isTab;
  const HelpdeskScreen({super.key, this.isTab = false});

  static const Color deepCobalt = AuthUiTokens.deepCobalt;
  static const Color royalBlue = AuthUiTokens.royalBlue;
  static const Color titleDark = AuthUiTokens.titleDark;
  static const Color textMuted = AuthUiTokens.textMuted;

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: deepCobalt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!isTab) ...[
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AuthUiTokens.inputBorder),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 17,
                            color: deepCobalt,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pusat Bantuan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'Layanan Nasabah Bank DMB',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Solid Cobalt Hero Card (matches Beranda Balance Card)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: deepCobalt,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: deepCobalt.withOpacity(0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -35,
                        top: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.06),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LAYANAN RESMI',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: AuthUiTokens.cyanAccent,
                                      letterSpacing: 0.9,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppContent.text('helpdesk.intro_title'),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    AppContent.text('helpdesk.intro_text'),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.84),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.headset_mic_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Text(
                'Kanal Komunikasi Resmi',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 10),

              _buildContactCard(
                context: context,
                icon: Icons.phone_in_talk_rounded,
                title: 'Call Center 24 Jam',
                subtitle: BankContact.callCenterDisplay,
                description: AppContent.text('helpdesk.call_center_desc'),
                buttonLabel: 'Salin Nomor',
                onAction: () {
                  Clipboard.setData(ClipboardData(text: BankContact.callCenterDial));
                  _showToast(context, 'Nomor Call Center disalin: ${BankContact.callCenterDisplay}');
                },
              ),
              const SizedBox(height: 12),

              _buildContactCard(
                context: context,
                icon: Icons.chat_bubble_outline_rounded,
                title: 'WhatsApp Customer Care',
                subtitle: BankContact.whatsAppDisplay,
                description: AppContent.text('helpdesk.whatsapp_desc'),
                buttonLabel: 'Salin WhatsApp',
                onAction: () {
                  Clipboard.setData(ClipboardData(text: BankContact.whatsAppDial));
                  _showToast(context, 'Nomor WhatsApp disalin: ${BankContact.whatsAppDisplay}');
                },
              ),
              const SizedBox(height: 12),

              _buildContactCard(
                context: context,
                icon: Icons.mail_outline_rounded,
                title: 'Email Layanan Nasabah',
                subtitle: BankContact.email,
                description: AppContent.text('helpdesk.email_desc'),
                buttonLabel: 'Salin Email',
                onAction: () {
                  Clipboard.setData(ClipboardData(text: BankContact.email));
                  _showToast(context, 'Alamat email disalin');
                },
              ),

              const SizedBox(height: 22),

              Text(
                'Kantor Operasional Bank DMB',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8EEF6)),
                  boxShadow: [
                    BoxShadow(
                      color: royalBlue.withOpacity(0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: AuthUiTokens.softBlueBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.apartment_rounded,
                            color: deepCobalt,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kantor Pusat Operasional',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: titleDark,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                BankContact.headOfficeAddress,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFF1F5F9), height: 1),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1.5),
                          child: Icon(Icons.access_time_rounded, size: 15, color: royalBlue),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Jam Layanan Kantor: ${BankContact.officeHours}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: textMuted,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required String buttonLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: royalBlue.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AuthUiTokens.softBlueBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: deepCobalt, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: royalBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: deepCobalt,
                side: const BorderSide(color: AuthUiTokens.softBlueBorder),
                backgroundColor: AuthUiTokens.softBlueBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
              ),
              onPressed: onAction,
              child: Text(
                buttonLabel,
                style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
