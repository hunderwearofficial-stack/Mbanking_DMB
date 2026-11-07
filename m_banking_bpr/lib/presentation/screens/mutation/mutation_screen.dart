import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

  void _showTransactionReceipt(BuildContext context, MutationModel m) {
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
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: m.isCredit ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: m.isCredit ? const Color(0xFF86EFAC) : const Color(0xFFFECDD3),
                  ),
                ),
                child: Icon(
                  m.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  color: m.isCredit ? AppColors.primary : AppColors.expense,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                m.isCredit ? 'DANA MASUK (KREDIT)' : 'DANA KELUAR (DEBIT)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: m.isCredit ? AppColors.primary : AppColors.expense,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: m.isCredit ? AppColors.primary : AppColors.expense,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),
            _buildReceiptRow('Status Transaksi', 'BERHASIL (SUCCESS)', isHighlight: true),
            _buildReceiptRow('Waktu Transaksi', CurrencyFormatter.formatDateFull(m.createdAt)),
            _buildReceiptRow('Nomor Referensi', m.referenceNumber),
            _buildReceiptRow('Keterangan', m.description),
            _buildReceiptRow('Nomor Rekening', m.accountNumber),
            _buildReceiptRow('Saldo Setelahnya', CurrencyFormatter.formatRupiah(m.balanceAfter)),
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
                child: const Text('Tutup Bukti Mutasi', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isHighlight ? AppColors.primary : AppColors.textPrimary,
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          children: [
            Text(
              'Riwayat Mutasi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            Text(
              'PT BPR DANA MANDIRI BOGOR',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: BlocBuilder<AccountCubit, AccountState>(
        builder: (context, state) {
          if (state is AccountLoading) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (state is AccountError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
                    const SizedBox(height: 12),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => context.read<AccountCubit>().refresh(),
                      child: const Text('Muat Ulang Data'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is AccountLoaded) {
            final acc = state.account;
            final allMutations = state.mutations;

            // Calculate totals
            double totalCredit = 0;
            double totalDebit = 0;
            for (var m in allMutations) {
              if (m.isCredit) {
                totalCredit += m.amount;
              } else {
                totalDebit += m.amount;
              }
            }

            return Column(
              children: [
                // Top Executive Summary Card (Wondr style in Backoffice Teal)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF004D40), // Dark Teal
                        Color(0xFF00796B),
                        Color(0xFF00897B),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF004D40).withOpacity(0.2),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            acc.accountType,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              acc.accountNumber,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        CurrencyFormatter.formatRupiah(acc.balance),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.arrow_downward_rounded, color: Color(0xFF86EFAC), size: 14),
                                  const SizedBox(width: 4),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Uang Masuk', style: TextStyle(fontSize: 9, color: Colors.white70)),
                                      Text(
                                        CurrencyFormatter.formatRupiah(totalCredit),
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 24, color: Colors.white24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.arrow_upward_rounded, color: Color(0xFFFECDD3), size: 14),
                                  const SizedBox(width: 4),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Uang Keluar', style: TextStyle(fontSize: 9, color: Colors.white70)),
                                      Text(
                                        CurrencyFormatter.formatRupiah(totalDebit),
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Filter Tabs (Semua, Uang Masuk, Uang Keluar)
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    tabs: const [
                      Tab(text: 'Semua Transaksi'),
                      Tab(text: 'Uang Masuk (CR)'),
                      Tab(text: 'Uang Keluar (DB)'),
                    ],
                    onTap: (_) => setState(() {}),
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),

                // Mutations List
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

  Widget _buildMutationList(List<MutationModel> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<AccountCubit>().refresh(),
        color: AppColors.primary,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 54, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'Tidak ada mutasi transaksi pada periode ini',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final m = items[index];
          return InkWell(
            onTap: () => _showTransactionReceipt(context, m),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: m.isCredit ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: m.isCredit ? const Color(0xFFDCFCE7) : const Color(0xFFFFE4E6),
                          ),
                        ),
                        child: Text(
                          m.isCredit ? 'DANA MASUK (CR)' : 'DANA KELUAR (DB)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: m.isCredit ? AppColors.primary : AppColors.expense,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatDate(m.createdAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    m.description,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Ref: ${m.referenceNumber}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: m.isCredit ? AppColors.primary : AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 18, color: Color(0xFFF1F5F9)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Saldo Setelah Transaksi:',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      Text(
                        CurrencyFormatter.formatRupiah(m.balanceAfter),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
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
