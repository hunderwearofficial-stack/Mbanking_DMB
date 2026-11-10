import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class HelpdeskScreen extends StatelessWidget {
  final bool isTab;
  const HelpdeskScreen({super.key, this.isTab = false});

  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: titleDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !isTab,
        leading: isTab
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Column(
          children: [
            Text(
              'Pusat Bantuan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'LAYANAN NASABAH BANK DMB',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: royalBlue,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Hero Help Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0754A8),
                    Color(0xFF087299),
                    Color(0xFF149752),
                  ],
                  stops: [0.0, 0.60, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0754A8).withOpacity(0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'LAYANAN RESMI',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Butuh Bantuan?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tim Customer Care Bank DMB siap melayani Anda melalui kanal komunikasi resmi.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: Colors.white.withOpacity(0.88),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.35)),
                    ),
                    child: const Center(
                      child: Icon(Icons.headset_mic_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 2. Kanal Kontak Resmi
            Text(
              'Kanal Komunikasi Resmi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 10),

            _buildContactCard(
              context: context,
              icon: Icons.phone_in_talk_rounded,
              iconBg: const Color(0xFFEFF6FF),
              iconColor: royalBlue,
              title: 'Call Center 24 Jam',
              subtitle: '(0251) 832-1234',
              description: 'Layanan bebas pulsa untuk nasabah aktif',
              buttonLabel: 'Salin Nomor',
              onAction: () {
                Clipboard.setData(const ClipboardData(text: '02518321234'));
                _showToast(context, 'Nomor Call Center disalin: (0251) 832-1234');
              },
            ),
            const SizedBox(height: 10),

            _buildContactCard(
              context: context,
              icon: Icons.chat_bubble_outline_rounded,
              iconBg: const Color(0xFFF0FDF4),
              iconColor: dmbGreen,
              title: 'WhatsApp Customer Care',
              subtitle: '0811-9988-7766',
              description: 'Akun bisnis resmi terverifikasi dengan centang hijau',
              buttonLabel: 'Chat WhatsApp',
              onAction: () {
                Clipboard.setData(const ClipboardData(text: '081199887766'));
                _showToast(context, 'Nomor WhatsApp disalin: 0811-9988-7766');
              },
            ),
            const SizedBox(height: 10),

            _buildContactCard(
              context: context,
              icon: Icons.mail_outline_rounded,
              iconBg: const Color(0xFFF8FAFC),
              iconColor: primaryNavy,
              title: 'Email Layanan Nasabah',
              subtitle: 'layanan@bprdanamandiri.co.id',
              description: 'Dukungan surat elektronik resmi Bank DMB',
              buttonLabel: 'Salin Email',
              onAction: () {
                Clipboard.setData(const ClipboardData(text: 'layanan@bprdanamandiri.co.id'));
                _showToast(context, 'Alamat email disalin');
              },
            ),

            const SizedBox(height: 24),

            // 3. Kantor Operasional
            Text(
              'Kantor Operasional Bank DMB',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
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
                border: Border.all(color: borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.apartment_rounded, color: royalBlue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kantor Pusat Operasional',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Jl. Pajajaran No. 88, Kota Bogor, Jawa Barat 16128',
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
                        child: Icon(Icons.access_time_rounded, size: 15, color: textMuted),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Jam Layanan Kantor: Senin - Jumat (08.00 - 15.30 WIB)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
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

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required BuildContext context,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
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
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Center(child: Icon(icon, color: iconColor, size: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
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
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: royalBlue,
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                backgroundColor: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
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

