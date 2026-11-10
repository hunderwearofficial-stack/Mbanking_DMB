import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../account/account_info_screen.dart';
import '../mutation/mutation_screen.dart';
import '../statement/estatement_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../auth/terms_conditions_screen.dart';
import '../auth/login_screen.dart';
import 'security_settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  final bool isTab;
  const ProfileScreen({super.key, this.isTab = false});

  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color dmbRed = Color(0xFFDC2626);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  void _showLogoutDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: borderLight,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Icon(Icons.logout_rounded, color: dmbRed, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Keluar dari Aplikasi?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sesi login Anda di DMB Mobile akan diakhiri dengan aman. Anda dapat masuk kembali kapan saja.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted, height: 1.45),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: titleDark,
                        side: const BorderSide(color: borderLight, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => Navigator.of(bottomSheetContext).pop(),
                      child: Text(
                        'Batal',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: dmbRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.of(bottomSheetContext).pop();
                        context.read<AuthCubit>().logout();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      child: Text(
                        'Ya, Keluar',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final accountState = context.watch<AccountCubit>().state;

    String fullName = 'Wahyu Nafeeza';
    String phone = '';

    if (authState is AuthAuthenticated) {
      if (authState.user.fullName.isNotEmpty) fullName = authState.user.fullName;
      phone = authState.user.phoneNumber;
    }
    if (accountState is AccountLoaded && accountState.account.holderName.isNotEmpty) {
      fullName = accountState.account.holderName;
    }

    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'W';

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
              'Profil Saya',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'PENGATURAN & INFORMASI AKUN',
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
            // 1. Profile Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
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
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: primaryNavy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phone.isNotEmpty ? phone : 'Nasabah Resmi Bank DMB',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'NASABAH TERVERIFIKASI',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. Section: Akun & Portofolio
            Text(
              'Akun & Portofolio',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            _buildMenuCard(
              children: [
                _buildMenuItem(
                  icon: Icons.article_outlined,
                  iconColor: royalBlue,
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Informasi Rekening & CIF',
                  subtitle: 'Data CIF & seluruh portofolio tabungan',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                _buildMenuItem(
                  icon: Icons.history_rounded,
                  iconColor: dmbGreen,
                  iconBg: const Color(0xFFF0FDF4),
                  title: 'Riwayat Transaksi',
                  subtitle: 'Catatan mutasi uang masuk & keluar',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MutationScreen()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                _buildMenuItem(
                  icon: Icons.picture_as_pdf_outlined,
                  iconColor: primaryNavy,
                  iconBg: const Color(0xFFF1F5F9),
                  title: 'e-Statement Rekening',
                  subtitle: 'Unduh rekening koran digital PDF',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EStatementScreen()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 22),

            // 3. Section: Keamanan & Akses
            Text(
              'Keamanan & Sandi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            _buildMenuCard(
              children: [
                _buildMenuItem(
                  icon: Icons.security_rounded,
                  iconColor: royalBlue,
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Pengaturan Keamanan & PIN',
                  subtitle: 'Ubah PIN transaksi, biometrik, & sesi login',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 22),

            // 4. Section: Bantuan & Ketentuan
            Text(
              'Layanan & Bantuan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            _buildMenuCard(
              children: [
                _buildMenuItem(
                  icon: Icons.headset_mic_outlined,
                  iconColor: royalBlue,
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Pusat Bantuan 24 Jam',
                  subtitle: 'Call Center, WhatsApp & Email resmi',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                _buildMenuItem(
                  icon: Icons.policy_outlined,
                  iconColor: dmbGreen,
                  iconBg: const Color(0xFFF0FDF4),
                  title: 'Syarat & Ketentuan',
                  subtitle: 'Kebijakan privasi & aturan perbankan',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TermsConditionsScreen()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 5. Logout Action
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: dmbRed,
                  side: const BorderSide(color: Color(0xFFFECACA), width: 1.5),
                  backgroundColor: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _showLogoutDialog(context),
                icon: const Icon(Icons.logout_rounded, size: 19),
                label: Text(
                  'Keluar dari Akun',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // App Version Footer
            Center(
              child: Column(
                children: [
                  Text(
                    'DMB Mobile v1.0.0',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'PT BPR Dana Mandiri Bogor • Terdaftar & Diawasi OJK',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: textMuted),
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

  Widget _buildMenuCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
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
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Center(child: Icon(icon, color: iconColor, size: 20)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 1.5),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
          ],
        ),
      ),
    );
  }
}

