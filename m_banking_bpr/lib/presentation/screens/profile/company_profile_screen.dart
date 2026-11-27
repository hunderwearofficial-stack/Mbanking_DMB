import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/content/app_content.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../widgets/auth_ui_kit.dart';

class CompanyProfileScreen extends StatelessWidget {
  const CompanyProfileScreen({super.key});

  static const Color deepCobalt = AuthUiTokens.deepCobalt;
  static const Color royalBlue = AuthUiTokens.royalBlue;
  static const Color titleDark = AuthUiTokens.titleDark;
  static const Color textMuted = AuthUiTokens.textMuted;

  @override
  Widget build(BuildContext context) {
    final config = DynamicConfigService().config;
    final bankName = config.bankName.isNotEmpty ? config.bankName : 'PT BPR Dana Mandiri Bogor';
    final heroTitle = AppContent.text('company.hero_title');
    final establishedYear = AppContent.text('company.established_year');
    final aboutDesc = AppContent.text('company.about_description');
    final vision = AppContent.text('company.vision');
    final missionLines = AppContent.text('company.mission')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final lpsText = AppContent.text('company.lps_guarantee_text');

    final branches = AppContent.text('company.branches')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
          final sepIdx = line.indexOf('|');
          if (sepIdx > 0) {
            return (
              name: line.substring(0, sepIdx).trim(),
              address: line.substring(sepIdx + 1).trim(),
            );
          }
          return (name: line, address: '');
        })
        .toList();

    final canPop = Navigator.canPop(context);

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DmbPageHeader(
              title: 'Tentang Bank DMB',
              subtitle: bankName,
              showBack: canPop,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 14, 18, canPop ? 28 : 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

              // Architectural Photo Showcase Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: deepCobalt,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: deepCobalt.withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 245,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ContentImage(
                              'company.hero_image',
                              fit: BoxFit.cover,
                              placeholder: Image.asset(
                                'assets/images/home_header_landmark.jpg',
                                fit: BoxFit.cover,
                              ),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    deepCobalt.withOpacity(0.0),
                                    deepCobalt.withOpacity(0.55),
                                    deepCobalt,
                                  ],
                                  stops: const [0.35, 0.72, 1.0],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 18,
                              right: 18,
                              bottom: 14,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    heroTitle,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.25,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    aboutDesc,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.92),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF043C88),
                          border: Border(
                            top: BorderSide(color: Colors.white.withOpacity(0.14)),
                          ),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              _buildStatColumn('Tahun Berdiri', establishedYear),
                              _buildStatDivider(),
                              _buildStatColumn('Kantor Layanan', '${branches.length}'),
                              _buildStatDivider(),
                              _buildStatColumn('Diawasi', 'OJK'),
                              _buildStatDivider(),
                              _buildStatColumn('Dijamin', 'LPS'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Text(
                'Jaringan Kantor Layanan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 10),

              ...List.generate(branches.length, (idx) {
                final b = branches[idx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE8EEF6)),
                      boxShadow: [
                        BoxShadow(
                          color: royalBlue.withOpacity(0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
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
                            size: 20,
                            color: deepCobalt,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.name,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: titleDark,
                                ),
                              ),
                              if (b.address.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  b.address,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: textMuted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),

              _buildSectionCard(
                title: 'Visi & Misi',
                icon: Icons.flag_rounded,
                children: [
                  Text(
                    'Visi Perusahaan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vision,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      color: textMuted,
                      height: 1.5,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                  ),
                  Text(
                    'Misi Perusahaan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...missionLines.map(_buildBulletPoint),
                ],
              ),

              const SizedBox(height: 14),

              _buildSectionCard(
                title: 'Legalitas & Perlindungan Nasabah',
                icon: Icons.verified_user_rounded,
                children: [
                  _buildRegulationRow(
                    icon: Icons.account_balance_rounded,
                    title: 'Otoritas Jasa Keuangan (OJK)',
                    desc: '$bankName berizin dan diawasi secara resmi oleh Otoritas Jasa Keuangan (OJK).',
                  ),
                  const SizedBox(height: 12),
                  _buildRegulationRow(
                    icon: Icons.health_and_safety_rounded,
                    title: 'Lembaga Penjamin Simpanan (LPS)',
                    desc: lpsText,
                  ),
                  const SizedBox(height: 12),
                  _buildRegulationRow(
                    icon: Icons.lock_rounded,
                    title: 'Perlindungan Data Pribadi (UU PDP)',
                    desc: 'Seluruh sistem dan transmisi data dilindungi enkripsi kriptografis sesuai standar keamanan perbankan nasional.',
                  ),
                ],
              ),

              const SizedBox(height: 22),

              Center(
                child: Text(
                  '\u00A9 ${DateTime.now().year} $bankName. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildStatColumn(String label, String value) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildStatDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white.withOpacity(0.22),
    );
  }

  static Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AuthUiTokens.softBlueBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: deepCobalt, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: titleDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  static Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 10),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: royalBlue,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: const Color(0xFF475569),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildRegulationRow({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: royalBlue, size: 20),
        const SizedBox(width: 12),
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
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
