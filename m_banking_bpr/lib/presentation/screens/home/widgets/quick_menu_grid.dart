import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/models/loan_model.dart';
import '../../../../data/repositories/account_repository.dart';
import '../../../blocs/account/account_cubit.dart';
import '../../../blocs/account/account_state.dart';
import '../../mutation/mutation_screen.dart';
import '../../product/product_simulator_sheet.dart';
import '../../product/product_catalog_screen.dart';
import '../../profile/security_settings_screen.dart';
import '../../helpdesk/helpdesk_screen.dart';
import '../../account/account_info_screen.dart';
import '../../loan/loan_screen.dart';
import '../../deposit/deposit_screen.dart';

class FigmaMenuGrid extends StatelessWidget {
  const FigmaMenuGrid({super.key});

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
              'Layanan pembayaran pihak ketiga (PPOB & Biller) sedang dalam integrasi gateway switching untuk kenyamanan transaksi Anda.',
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
    final accState = context.read<AccountCubit>().state;
    double totalCredit = 0;
    double totalDebit = 0;
    int txCount = 0;
    String accNo = '-';
    String holderName = 'Nasabah Bank DMB';
    double endBalance = 0;

    if (accState is AccountLoaded) {
      accNo = accState.account.accountNumber;
      holderName = accState.account.holderName;
      endBalance = accState.account.balance;
      txCount = accState.mutations.length;
      for (final m in accState.mutations) {
        if (m.isCredit) {
          totalCredit += m.amount;
        } else {
          totalDebit += m.amount;
        }
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'e-Statement Rekening Koran',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Rekening $accNo • $holderName',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Total Mutasi Terdata', '$txCount Transaksi'),
                  _buildDetailRow('Total Dana Masuk (Kredit)', '+ ${CurrencyFormatter.formatRupiah(totalCredit)}'),
                  _buildDetailRow('Total Dana Keluar (Debit)', '- ${CurrencyFormatter.formatRupiah(totalDebit)}'),
                  const Divider(height: 16),
                  _buildDetailRow('Saldo Akhir Saat Ini', CurrencyFormatter.formatRupiah(endBalance)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildStatementOption(
              sheetCtx,
              'Ringkasan e-Statement Bulan Berjalan',
              '$txCount Transaksi • Saldo Akhir ${CurrencyFormatter.formatRupiah(endBalance)}',
              onShare: () {
                final text = '=== E-STATEMENT RESMI BANK DMB ===\n'
                    'PT BPR DANA MANDIRI BOGOR\n'
                    'Nama Nasabah : $holderName\n'
                    'No. Rekening : $accNo\n'
                    'Jumlah Mutasi: $txCount Transaksi\n'
                    'Total Kredit : + ${CurrencyFormatter.formatRupiah(totalCredit)}\n'
                    'Total Debit  : - ${CurrencyFormatter.formatRupiah(totalDebit)}\n'
                    'Saldo Akhir  : ${CurrencyFormatter.formatRupiah(endBalance)}\n'
                    '==================================';
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ringkasan e-Statement resmi berhasil disalin ke Clipboard!'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStatementOption(BuildContext context, String period, String subtitle, {required VoidCallback onShare}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(period, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.copy_all_rounded, size: 16),
            label: const Text('Salin', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            onPressed: onShare,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color royalBlue = Color(0xFF0062E3);
    const Color titleDark = Color(0xFF0B2546);

    // 4 Menu Utama Resmi 100% Sesuai Endpoint Core Banking OpenAPI
    // 1. Mutasi Tabungan  -> POST /api/savings-account-mutations (Postman #8)
    // 2. Fasilitas Pinjaman -> POST /api/loan-accounts & /api/loan-account-detail (Postman #9 & #10)
    // 3. Portofolio Deposito -> POST /api/deposit-accounts & /api/deposit-account-detail (Postman #11 & #12)
    // 4. Katalog Produk    -> POST /api/products (Postman #4)
    final List<Map<String, dynamic>> items = [
      {
        'title': 'Mutasi\nTabungan',
        'icon': Icons.history_rounded,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MutationScreen()),
          );
        },
      },
      {
        'title': 'Fasilitas\nPinjaman',
        'icon': Icons.credit_score_outlined,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoanScreen()),
          );
        },
      },
      {
        'title': 'Portofolio\nDeposito',
        'icon': Icons.savings_outlined,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DepositScreen()),
          );
        },
      },
      {
        'title': 'Katalog\nProduk',
        'icon': Icons.auto_stories_outlined,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProductCatalogScreen()),
          );
        },
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Menu Utama',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: titleDark,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),

          // 4 Kolom Menu Sesuai API CBS DMB
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.72,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final item = items[index];

              return InkWell(
                onTap: item['onTap'] as VoidCallback,
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 62,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFF3F8FE),
                            Color(0xFFE8F1FC),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD6E6F9)),
                        boxShadow: [
                          BoxShadow(
                            color: royalBlue.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          item['icon'] as IconData,
                          color: royalBlue,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      height: 32,
                      child: Text(
                        item['title'] as String,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                          height: 1.25,
                        ),
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

