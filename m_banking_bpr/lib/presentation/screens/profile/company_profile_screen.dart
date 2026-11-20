import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/services/dynamic_config_service.dart';

class CompanyProfileScreen extends StatelessWidget {
  const CompanyProfileScreen({super.key});

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color bgCanvas = AppColors.bgCanvas;
  static const Color borderLight = AppColors.borderLight;

  @override
  Widget build(BuildContext context) {
    final config = DynamicConfigService().config;
    final bankName = config.bankName.isNotEmpty ? config.bankName : 'PT BPR Dana Mandiri Bogor';
    final heroImageUrl = AppContent.imageUrl('company.hero_image');
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F2),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Image + Overlapping Blue Stats Bar (responsive, no fixed height / no overlap)
            Stack(
              children: [
                Positioned.fill(
                  bottom: 34,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (heroImageUrl != null)
                        ContentImage(
                          heroImageUrl,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF0A2A66), Color(0xFF134A8E)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0A2A66), Color(0xFF134A8E)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.25),
                              Colors.black.withValues(alpha: 0.12),
                              Colors.black.withValues(alpha: 0.72),
                            ],
                            stops: const [0.0, 0.35, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Row(
                          children: [
                            Material(
                              color: Colors.white,
                              shape: const CircleBorder(),
                              elevation: 1,
                              shadowColor: Colors.black.withValues(alpha: 0.15),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).pop(),
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.chevron_left_rounded,
                                    size: 24,
                                    color: Color(0xFF0A2A66),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Profil Bank DMB',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x55000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: heroImageUrl != null ? 96 : 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heroTitle,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.2,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            aboutDesc,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF144296),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0A2A66).withValues(alpha: 0.22),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
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
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Kantor Layanan List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(branches.length, (idx) {
                    final b = branches[idx];
                    final isEven = idx.isEven;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.025),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isEven ? const Color(0xFFEFF6FF) : const Color(0xFFE6F7F1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.apartment_rounded,
                                size: 21,
                                color: isEven ? const Color(0xFF0A2A66) : const Color(0xFF0F9D76),
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
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0A2A66),
                                    ),
                                  ),
                                  if (b.address.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      b.address,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12.5,
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

                  const SizedBox(height: 6),

                  // Visi & Misi
                  _buildSectionCard(
                    title: 'Visi & Misi',
                    icon: Icons.flag_outlined,
                    iconColor: dmbGreen,
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
                        child: Divider(height: 1, color: borderLight),
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

                  const SizedBox(height: 16),

                  // Legalitas & Regulasi
                  _buildSectionCard(
                    title: 'Legalitas & Perlindungan Nasabah',
                    icon: Icons.shield_outlined,
                    iconColor: const Color(0xFFD97706),
                    children: [
                      _buildRegulationRow(
                        icon: Icons.account_balance_outlined,
                        title: 'Otoritas Jasa Keuangan (OJK)',
                        desc: '$bankName berizin dan diawasi secara resmi oleh Otoritas Jasa Keuangan (OJK).',
                      ),
                      const SizedBox(height: 12),
                      _buildRegulationRow(
                        icon: Icons.health_and_safety_outlined,
                        title: 'Lembaga Penjamin Simpanan (LPS)',
                        desc: lpsText,
                      ),
                      const SizedBox(height: 12),
                      _buildRegulationRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'Perlindungan Data Pribadi (UU PDP)',
                        desc: 'Seluruh sistem dan transmisi data dilindungi enkripsi kriptografis sesuai standar keamanan perbankan nasional.',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Footer
                  Center(
                    child: Text(
                      '© ${DateTime.now().year} $bankName. All rights reserved.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
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
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w900,
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
      color: Colors.white.withValues(alpha: 0.25),
    );
  }

  static Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
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
              color: dmbGreen,
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
        Icon(icon, color: primaryNavy, size: 20),
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
