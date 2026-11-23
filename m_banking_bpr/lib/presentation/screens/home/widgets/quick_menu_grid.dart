import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../deposit/deposit_screen.dart';
import '../../loan/loan_screen.dart';
import '../../mutation/mutation_screen.dart';
import '../../product/product_catalog_screen.dart';
import '../../profile/company_profile_screen.dart';

class FigmaMenuGrid extends StatelessWidget {
  const FigmaMenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final List<({
      String title,
      String subtitle,
      IconData icon,
      Color iconBg,
      Color iconColor,
      VoidCallback onTap,
    })> items = [
      (
        title: 'Mutasi Tabungan',
        subtitle: 'Lihat riwayat',
        icon: Icons.history_rounded,
        iconBg: const Color(0xFFEBF2FF),
        iconColor: const Color(0xFF0A2A66),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MutationScreen()),
          );
        },
      ),
      (
        title: 'Fasilitas Pinjaman',
        subtitle: 'Cek angsuran',
        icon: Icons.account_balance_wallet_outlined,
        iconBg: const Color(0xFFE3F7EE),
        iconColor: const Color(0xFF0F9D76),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoanScreen()),
          );
        },
      ),
      (
        title: 'Portofolio Deposito',
        subtitle: 'Pantau simpanan',
        icon: Icons.lock_outline_rounded,
        iconBg: const Color(0xFFE0F2FE),
        iconColor: const Color(0xFF0369A1),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DepositScreen()),
          );
        },
      ),
      (
        title: 'Katalog Produk',
        subtitle: 'Kenali produk DMB',
        icon: Icons.grid_view_rounded,
        iconBg: const Color(0xFFEDE9FE),
        iconColor: const Color(0xFF4F46E5),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProductCatalogScreen()),
          );
        },
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Menu Utama',
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            color: AppColors.titleDark,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(child: _buildMenuCard(items[0])),
            const SizedBox(width: 12),
            Expanded(child: _buildMenuCard(items[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildMenuCard(items[2])),
            const SizedBox(width: 12),
            Expanded(child: _buildMenuCard(items[3])),
          ],
        ),

        const SizedBox(height: 12),

        // Full-width "Tentang DMB" card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CompanyProfileScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F7EE),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF0F9D76),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tentang DMB',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.titleDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Profil dan kontak kami',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuCard(({
    String title,
    String subtitle,
    IconData icon,
    Color iconBg,
    Color iconColor,
    VoidCallback onTap,
  }) item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: item.iconBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    item.icon,
                    color: item.iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.titleDark,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
