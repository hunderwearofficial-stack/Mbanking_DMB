import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/models/account_model.dart';
import '../../../../data/models/loan_model.dart';
import '../../../blocs/auth/auth_cubit.dart';
import '../../../blocs/auth/auth_state.dart';
import '../../mutation/mutation_screen.dart';

class FigmaBalanceCardCarousel extends StatefulWidget {
  final AccountModel? account;
  final bool isBalanceVisible;
  final VoidCallback onToggleVisibility;

  const FigmaBalanceCardCarousel({
    super.key,
    required this.account,
    required this.isBalanceVisible,
    required this.onToggleVisibility,
  });

  @override
  State<FigmaBalanceCardCarousel> createState() => _FigmaBalanceCardCarouselState();
}

class _FigmaBalanceCardCarouselState extends State<FigmaBalanceCardCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _copyText(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('$label $text berhasil disalin'),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAccountDetailsModal(BuildContext context, AccountModel? acc) {
    final authState = context.read<AuthCubit>().state;
    String userCif = '-';
    String userFullName = '-';
    if (authState is AuthAuthenticated) {
      userCif = authState.user.cif;
      userFullName = authState.user.fullName;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
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
                      child: const Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Informasi Rekening CBS',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                          Text(
                            'Data Real-Time Core Banking System BPR DMB',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDetailRow('Nama Pemilik (CBS)', (acc != null && acc.holderName.isNotEmpty) ? acc.holderName : userFullName),
                _buildDetailRow('Nama Produk', acc?.accountType ?? 'Tabungan Mandiri DMB'),
                if (acc != null && acc.productCode.isNotEmpty)
                  _buildDetailRow('Kode Produk CBS', acc.productCode),
                _buildDetailRow('Nomor Rekening', acc?.accountNumber ?? '-'),
                _buildDetailRow('Nomor CIF', userCif),
                _buildDetailRow('Saldo Akhir (CBS)', CurrencyFormatter.formatRupiah(acc?.balance ?? 0)),
                _buildDetailRow('Saldo Efektif', CurrencyFormatter.formatRupiah(acc?.effectiveBalance ?? 0)),
                _buildDetailRow('Saldo Minimum', CurrencyFormatter.formatRupiah(acc?.minimumBalance ?? 0)),
                _buildDetailRow('Saldo Blokir', CurrencyFormatter.formatRupiah(acc?.blockedBalance ?? 0)),
                _buildDetailRow('Status Rekening', 'Aktif (Live CBS OpenAPI)'),
                if (acc?.cbsRefId != null && acc!.cbsRefId!.isNotEmpty)
                  _buildDetailRow('Ref ID CBS', acc.cbsRefId!),
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
                    child: const Text('Tutup Informasi', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLoanDetailsModal(BuildContext context, LoanModel loan) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
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
                            'Fasilitas Pinjaman',
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

                // Summary Card inside modal
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
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
                        child: LinearProgressIndicator(
                          value: 0.30, // 30% terbayar
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
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

  @override
  Widget build(BuildContext context) {
    final balance = widget.account?.balance ?? 0.0;
    final accNo = (widget.account != null && widget.account!.accountNumber.isNotEmpty)
        ? widget.account!.accountNumber
        : '-';
    final accTitle = (widget.account != null && widget.account!.accountType.isNotEmpty)
        ? widget.account!.accountType.toUpperCase()
        : 'TABUNGAN MANDIRI DMB';
    const loan = LoanModel.demoLoan;

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            children: [
              // Card 1: Tabungan Mandiri DMB (wondr luxury teal card - Live CBS)
              _buildWondrCard(
                context: context,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF00382E), // Deep luxury midnight teal
                    Color(0xFF005B4D),
                    Color(0xFF00897B), // Official Backoffice Teal
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                brandTag: 'BANK DMB',
                title: accTitle,
                accNo: accNo,
                accLabel: 'No. Rekening',
                amountLabel: 'Total saldo',
                amount: balance,
                chipColor: const Color(0xFFFFD54F),
                primaryActionLabel: 'Detail',
                primaryActionIcon: Icons.info_outline_rounded,
                onPrimaryAction: () => _showAccountDetailsModal(context, widget.account),
                secondaryActionLabel: 'Mutasi',
                secondaryActionIcon: Icons.history_rounded,
                onSecondaryAction: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MutationScreen()),
                  );
                },
              ),

              // Card 2: Pinjaman / Kredit Produktif BPR (Wondr style)
              _buildWondrCard(
                context: context,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF1E293B), // Slate 800
                    Color(0xFF0F766E), // Deep Teal
                    Color(0xFF00897B), // Backoffice Teal
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                brandTag: 'PINJAMAN DMB',
                title: 'KREDIT MODAL KERJA',
                accNo: loan.loanNumber,
                accLabel: 'No. Akad',
                amountLabel: 'Sisa pinjaman (Baki Debet)',
                amount: loan.remainingPrincipal,
                chipColor: const Color(0xFF67E8F9),
                primaryActionLabel: 'Rincian',
                primaryActionIcon: Icons.receipt_long_rounded,
                onPrimaryAction: () => _showLoanDetailsModal(context, loan),
                secondaryActionLabel: 'Jadwal',
                secondaryActionIcon: Icons.calendar_month_rounded,
                onSecondaryAction: () => _showLoanDetailsModal(context, loan),
              ),

              // Card 3: Deposito Berjangka DMB
              _buildWondrCard(
                context: context,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0A3B66), // Corporate Navy DMB
                    Color(0xFF0E528E),
                    Color(0xFF00897B),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                brandTag: 'SIMPANAN',
                title: 'DEPOSITO BERJANGKA DMB',
                accNo: '5001008009',
                accLabel: 'No. Bilyet',
                amountLabel: 'Total deposito (6.25% p.a.)',
                amount: 50000000.0,
                chipColor: const Color(0xFFFFD54F),
                primaryActionLabel: 'Detail',
                primaryActionIcon: Icons.info_outline_rounded,
                onPrimaryAction: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bilyet Deposito No. 5001008009 - Bunga 6.25% p.a. Jatuh Tempo 2027'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                secondaryActionLabel: 'Simulasi',
                secondaryActionIcon: Icons.calculate_rounded,
                onSecondaryAction: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Simulasi Deposito BPR DMB: Hasil bunga bulanan Rp 260.416 net'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Indicator dots for 3 cards
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final isActive = _currentPage == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: isActive ? 22 : 6,
              height: 5,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildWondrCard({
    required BuildContext context,
    required LinearGradient gradient,
    required String brandTag,
    required String title,
    required String accNo,
    required String accLabel,
    required String amountLabel,
    required double amount,
    required Color chipColor,
    required String primaryActionLabel,
    required IconData primaryActionIcon,
    required VoidCallback onPrimaryAction,
    required String secondaryActionLabel,
    required IconData secondaryActionIcon,
    required VoidCallback onSecondaryAction,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF004D40).withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              bottom: -40,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              right: 20,
              top: -30,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Brand Tag + Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                brandTag,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withOpacity(0.9),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 26,
                        height: 18,
                        decoration: BoxDecoration(
                          color: chipColor.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white.withOpacity(0.4), width: 0.8),
                        ),
                      ),
                    ],
                  ),

                  // Middle: Total saldo / Sisa Pinjaman & Eye Toggle
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        amountLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.isBalanceVisible
                                  ? CurrencyFormatter.formatRupiah(amount)
                                  : 'Rp ••••••••••',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: widget.onToggleVisibility,
                              child: Icon(
                                widget.isBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: Colors.white.withOpacity(0.9),
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Bottom Row: Account Number + Copy + Quick Action Pills
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: () => _copyText(context, accNo, accLabel),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.18)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    accNo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.copy_rounded, color: Colors.white, size: 11),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: onPrimaryAction,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.20),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(primaryActionIcon, color: Colors.white, size: 12),
                                  const SizedBox(width: 3),
                                  Text(
                                    primaryActionLabel,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          InkWell(
                            onTap: onSecondaryAction,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(secondaryActionIcon, color: const Color(0xFF004D40), size: 12),
                                  const SizedBox(width: 3),
                                  Text(
                                    secondaryActionLabel,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF004D40),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
