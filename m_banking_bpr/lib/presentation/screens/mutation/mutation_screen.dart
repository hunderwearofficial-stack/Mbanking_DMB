import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/mutation_model.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';

class MutationScreen extends StatefulWidget {
  const MutationScreen({super.key});

  @override
  State<MutationScreen> createState() => _MutationScreenState();
}

class _MutationScreenState extends State<MutationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Executive Brand Colors (Consistent with HomeScreen & DMB Identity)
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color dmbRed = Color(0xFFDC2626);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() => _selectedTabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<MutationModel> _filterMutations(List<MutationModel> list, int tabIndex) {
    if (tabIndex == 1) {
      return list.where((m) => m.isCredit).toList();
    } else if (tabIndex == 2) {
      return list.where((m) => !m.isCredit).toList();
    }
    return list;
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: titleDark,
      ),
    );
  }

  void _showTransactionReceipt(BuildContext context, MutationModel m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) => SafeArea(
        child: Container(
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
                    color: borderLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Status Icon Circle
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: m.isCredit ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: m.isCredit ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      m.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      color: m.isCredit ? dmbGreen : dmbRed,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: m.isCredit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    m.isCredit ? 'DANA MASUK (KREDIT)' : 'DANA KELUAR (DEBIT)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: m.isCredit ? dmbGreen : dmbRed,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Nominal
              Center(
                child: Text(
                  (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: m.isCredit ? dmbGreen : dmbRed,
                    letterSpacing: -0.4,
                  ),
                ),
              ),

              const SizedBox(height: 18),
              const Divider(color: borderLight, height: 1),
              const SizedBox(height: 14),

              _buildReceiptRow('Status Transaksi', 'BERHASIL', isSuccess: true),
              _buildReceiptRow('Waktu Transaksi', CurrencyFormatter.formatDate(m.createdAt)),
              _buildReceiptRow('Nomor Referensi', m.referenceNumber),
              _buildReceiptRow('Keterangan', m.description),
              _buildReceiptRow('Nomor Rekening', m.accountNumber),
              _buildReceiptRow('Saldo Setelahnya', CurrencyFormatter.formatRupiah(m.balanceAfter)),

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(modalCtx),
                  child: Text(
                    'Tutup Bukti Mutasi',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isSuccess = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: isSuccess ? FontWeight.w800 : FontWeight.w700,
                color: isSuccess ? dmbGreen : titleDark,
              ),
            ),
          ),
        ],
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Riwayat Transaksi',
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
      body: BlocBuilder<AccountCubit, AccountState>(
        builder: (context, state) {
          if (state is AccountLoading) {
            return const Center(child: CircularProgressIndicator(color: primaryNavy));
          }

          if (state is AccountError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: dmbRed),
                    const SizedBox(height: 12),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: textMuted),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () => context.read<AccountCubit>().refresh(),
                      child: Text(
                        'Muat Ulang Data',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is AccountLoaded) {
            final allMutations = state.mutations;

            return Column(
              children: [
                const SizedBox(height: 10),

                // Pill Filter Segmented Tabs (Semua, Uang Masuk, Uang Keluar)
                _buildPillTabBar(),

                // Mutations List Tabs
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMutationList(allMutations),
                      _buildMutationList(_filterMutations(allMutations, 1)),
                      _buildMutationList(_filterMutations(allMutations, 2)),
                    ],
                  ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  // ==================== PILL SEGMENTED TAB BAR ====================
  Widget _buildPillTabBar() {
    final tabs = ['Semua', 'Uang Masuk (CR)', 'Uang Keluar (DB)'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                _tabController.animateTo(index);
                setState(() => _selectedTabIndex = index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? royalBlue : textMuted,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ==================== MUTATION LIST VIEW ====================
  Widget _buildMutationList(List<MutationModel> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<AccountCubit>().refresh(),
        color: primaryNavy,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 70),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.receipt_long_outlined, size: 34, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Tidak ada transaksi pada filter ini',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Semua mutasi kredit & debit akan tercatat otomatis di sini.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<AccountCubit>().refresh(),
      color: primaryNavy,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final m = items[index];
          return InkWell(
            onTap: () => _showTransactionReceipt(context, m),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Row: Icon + Description + Amount
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon Circle
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: m.isCredit ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            m.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            color: m.isCredit ? dmbGreen : dmbRed,
                            size: 19,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Title & Date
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.description,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: titleDark,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              CurrencyFormatter.formatDate(m.createdAt),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Amount & Badge
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: m.isCredit ? dmbGreen : dmbRed,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: m.isCredit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m.isCredit ? 'CR' : 'DB',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: m.isCredit ? dmbGreen : dmbRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 8),

                  // Bottom Meta Row: Ref & Saldo Akhir
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Ref: ${m.referenceNumber}',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: textMuted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Text(
                            'Saldo: ',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                          ),
                          Text(
                            CurrencyFormatter.formatRupiah(m.balanceAfter),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: titleDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
