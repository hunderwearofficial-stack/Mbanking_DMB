import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'change_password_screen.dart';
import 'change_pin_screen.dart';

class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  // Executive DMB Brand Colors
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Keamanan & Sandi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'PT BPR DANA MANDIRI BOGOR',
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Text(
              'Pengaturan Akses Keamanan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 10),

            // Card 2 Menu Utama Keamanan
            Container(
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
                children: [
                  // 1. Ganti Password Login
                  ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                      );
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock_reset_rounded, color: royalBlue, size: 22),
                    ),
                    title: Text(
                      'Ganti Password Login',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleDark,
                      ),
                    ),
                    subtitle: Text(
                      'Perbarui kata sandi untuk masuk ke akun DMB Mobile',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: textMuted,
                        height: 1.3,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: textMuted),
                  ),

                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),

                  // 2. Ganti PIN Transaksi 6 Digit
                  ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChangePinScreen()),
                      );
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.dialpad_rounded, color: dmbGreen, size: 22),
                    ),
                    title: Text(
                      'Ganti PIN Transaksi 6 Digit',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleDark,
                      ),
                    ),
                    subtitle: Text(
                      'Ubah 6 digit PIN otorisasi transfer & pembayaran',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: textMuted,
                        height: 1.3,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: textMuted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Security Notice & Best Practice Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: royalBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tips Keamanan Perbankan',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: titleDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildTipItem(
                    '1. Jaga Kerahasiaan:',
                    'Jangan pernah membagikan Password, PIN, atau kode OTP kepada siapa pun termasuk pihak bank.',
                  ),
                  const SizedBox(height: 8),
                  _buildTipItem(
                    '2. Verifikasi Dua Langkah:',
                    'Setiap perubahan kata sandi dan PIN wajib diverifikasi melalui kode OTP demi keamanan rekening.',
                  ),
                  const SizedBox(height: 8),
                  _buildTipItem(
                    '3. Bantuan Resmi:',
                    'Hubungi Call Center resmi Bank DMB jika menemukan aktivitas mencurigakan pada akun Anda.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          desc,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: textMuted,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
