import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/models/loan_model.dart';
import '../../mutation/mutation_screen.dart';
import '../../transfer/transfer_screen.dart';

class FigmaMenuGrid extends StatelessWidget {
  const FigmaMenuGrid({super.key});

  void _showLoanModal(BuildContext context) {
    const loan = LoanModel.demoLoan;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Icon(Icons.credit_score_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pinjaman Aktif BPR',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      Text(
                        loan.productName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'LANCAR (KOL 1)',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Sisa Pokok (Baki Debet):',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        CurrencyFormatter.formatRupiah(loan.remainingPrincipal),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      value: 0.30,
                      minHeight: 6,
                      backgroundColor: Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Terbayar 30% (Rp 14.8jt)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Plafon: ${CurrencyFormatter.formatRupiah(loan.plafon)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            _buildDetailRow('Nomor Perjanjian Kredit', loan.loanNumber),
            _buildDetailRow('Angsuran per Bulan', CurrencyFormatter.formatRupiah(loan.monthlyInstallment)),
            _buildDetailRow('Jatuh Tempo Berikutnya', loan.nextDueDate),
            _buildDetailRow('Sisa Jangka Waktu', '${loan.remainingTenorMonths} dari ${loan.totalTenorMonths} Bulan'),
            _buildDetailRow('Suku Bunga Kredit', loan.interestRate),
            _buildDetailRow('Agunan / Jaminan', loan.collateral),
            _buildDetailRow('Kantor Cabang', loan.branchOffice),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup Rincian Pinjaman', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  static Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _showMaintenanceModal(BuildContext context, String serviceName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFB2DFDB)),
              ),
              child: const Icon(Icons.build_circle_rounded, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              serviceName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            const Text(
              'Layanan ini sedang dalam peningkatan sistem berkala untuk kenyamanan dan keamanan transaksi Anda. Silakan coba beberapa saat lagi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Mengerti', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showStatementModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.description_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'e-Statement Tabungan',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    Text(
                      'Rekening Koran Digital',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Unduh mutasi resmi rekening koran Bank DMB berformat PDF:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            _buildStatementOption(context, 'Bulan Ini (November 2026)', '4 Transaksi Terdata'),
            _buildStatementOption(context, 'Bulan Lalu (Oktober 2026)', '18 Transaksi Terdata'),
            _buildStatementOption(context, 'Kuartal 3 2026', 'Rekapitulasi Triwulan'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatementOption(BuildContext context, String period, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(period, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppColors.primary, size: 20),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Mengunduh e-Statement $period...'),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Exact 8 items in 4 columns x 2 rows matching wondr by BNI screenshot!
    final List<Map<String, dynamic>> items = [
      // Row 1
      {
        'title': 'Transfer',
        'icon': Icons.near_me_rounded,
        'bgColor': const Color(0xFFCCFBF1), // Mint Teal
        'iconColor': const Color(0xFF0F766E),
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TransferScreen()),
          );
        },
      },
      {
        'title': 'Pinjaman',
        'icon': Icons.credit_score_rounded,
        'bgColor': const Color(0xFFFFEDD5), // Soft Warm Orange (matching wondr TapCash style)
        'iconColor': const Color(0xFFEA580C),
        'onTap': () => _showLoanModal(context),
      },
      {
        'title': 'Bayar & Beli',
        'icon': Icons.receipt_rounded,
        'bgColor': const Color(0xFFEDE9FE), // Soft Lavender Periwinkle
        'iconColor': const Color(0xFF6D28D9),
        'onTap': () => _showMaintenanceModal(context, 'Bayar & Beli (PLN, Pulsa, PDAM)'),
      },
      {
        'title': 'E-Wallet',
        'icon': Icons.account_balance_wallet_rounded,
        'bgColor': const Color(0xFFCCFBF1), // Mint Teal
        'iconColor': const Color(0xFF0F766E),
        'onTap': () => _showMaintenanceModal(context, 'Top Up E-Wallet'),
      },
      // Row 2
      {
        'title': 'Mutasi',
        'icon': Icons.receipt_long_rounded,
        'bgColor': const Color(0xFFCCFBF1), // Mint Teal
        'iconColor': const Color(0xFF0F766E),
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MutationScreen()),
          );
        },
      },
      {
        'title': 'Detail Rek',
        'icon': Icons.account_balance_rounded,
        'bgColor': const Color(0xFFFEF3C7), // Warm Yellow
        'iconColor': const Color(0xFFD97706),
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MutationScreen()),
          );
        },
      },
      {
        'title': 'e-Statement',
        'icon': Icons.description_rounded,
        'bgColor': const Color(0xFFEDE9FE), // Soft Lavender
        'iconColor': const Color(0xFF6D28D9),
        'onTap': () => _showStatementModal(context),
      },
      {
        'title': 'Lihat Semua',
        'icon': Icons.grid_view_rounded,
        'bgColor': Colors.white,
        'iconColor': const Color(0xFF64748B),
        'isOutlined': true,
        'onTap': () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Semua Layanan Bank DMB telah ditampilkan di beranda'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Fitur pilihan kamu" + "Atur"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fitur pilihan kamu',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Atur Menu Cepat: Susun pintasan transaksi favorit Anda'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text(
                  'Atur',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFEA580C), // Orange like wondr
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4 Columns x 2 Rows Grid (Pure Wondr Style)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.76,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final isOutlined = item['isOutlined'] == true;

              return InkWell(
                onTap: item['onTap'] as VoidCallback,
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Squircle Container like wondr
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: item['bgColor'] as Color,
                        borderRadius: BorderRadius.circular(18),
                        border: isOutlined ? Border.all(color: const Color(0xFFCBD5E1), width: 1.2) : null,
                      ),
                      child: Center(
                        child: Icon(
                          item['icon'] as IconData,
                          color: item['iconColor'] as Color,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['title'] as String,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
