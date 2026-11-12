import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/mutation_model.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';

class MutationScreen extends StatefulWidget {
  final bool isTab;
  const MutationScreen({super.key, this.isTab = false});

  @override
  State<MutationScreen> createState() => _MutationScreenState();
}

class _MutationScreenState extends State<MutationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Date Filter State (Core Banking standard: max 31 days per range)
  late DateTime _startDate;
  late DateTime _endDate;
  late String _periodLabel;
  bool _isCustomFilterApplied = false;
  List<MutationModel>? _filteredMutations;
  bool _isFilterLoading = false;

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

    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
    final fmtStart = DateFormat('d MMM', 'id_ID').format(_startDate);
    final fmtEnd = DateFormat('d MMM yyyy', 'id_ID').format(_endDate);
    _periodLabel = 'Bulan Ini ($fmtStart - $fmtEnd)';
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

  Future<void> _applyDateFilter(
    DateTime start,
    DateTime end,
    String label, {
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        _isFilterLoading = true;
        _startDate = start;
        _endDate = end;
        _periodLabel = label;
        _isCustomFilterApplied = true;
      });
    }

    final sStr = DateFormat('yyyy-MM-dd').format(start);
    final eStr = DateFormat('yyyy-MM-dd').format(end);

    try {
      final repo = context.read<AccountCubit>().accountRepository;
      final accountState = context.read<AccountCubit>().state;
      String? accNo;
      if (accountState is AccountLoaded) {
        accNo = accountState.account.accountNumber;
      }

      final results = await repo.getMutations(
        limit: 50,
        accountNumber: accNo,
        startDate: sStr,
        endDate: eStr,
      );

      if (mounted) {
        setState(() {
          _filteredMutations = results;
          _isFilterLoading = false;
        });
        if (!silent) {
          _showToast('Menampilkan ${results.length} mutasi untuk periode $label');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFilterLoading = false);
        _showToast('Gagal memuat mutasi: $e');
      }
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _startDate.isAfter(now) ? now.subtract(const Duration(days: 30)) : _startDate,
        end: _endDate.isAfter(now) ? now : _endDate,
      ),
      helpText: 'Pilih Rentang Tanggal (Maks. 31 Hari)',
      cancelText: 'Batal',
      confirmText: 'Pilih',
      builder: (pickerCtx, child) {
        return Theme(
          data: Theme.of(pickerCtx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryNavy,
              onPrimary: Colors.white,
              onSurface: titleDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final daysDiff = picked.end.difference(picked.start).inDays;
      if (daysDiff > 31) {
        _showToast('Rentang tanggal maksimal 31 hari sesuai ketentuan core banking.');
        return;
      }

      final fmtStart = DateFormat('d MMM yyyy', 'id_ID').format(picked.start);
      final fmtEnd = DateFormat('d MMM yyyy', 'id_ID').format(picked.end);
      _applyDateFilter(picked.start, picked.end, '$fmtStart - $fmtEnd');
    }
  }

  void _showDateFilterBottomSheet() {
    final now = DateTime.now();
    final firstDayThisMonth = DateTime(now.year, now.month, 1);
    final lastDayLastMonth = DateTime(now.year, now.month, 0);
    final firstDayLastMonth = DateTime(lastDayLastMonth.year, lastDayLastMonth.month, 1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: borderLight, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month_rounded, color: royalBlue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pilih Periode Mutasi',
                          style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: titleDark),
                        ),
                        Text(
                          'Maksimal rentang 31 hari per permintaan',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: borderLight),
              const SizedBox(height: 12),

              // 1. Bulan Berjalan (Bulan Ini)
              _buildPeriodOption(
                sheetCtx,
                label: 'Bulan Berjalan',
                sublabel: '${DateFormat('d MMM yyyy', 'id_ID').format(firstDayThisMonth)} - ${DateFormat('d MMM yyyy', 'id_ID').format(now)}',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final fmtStart = DateFormat('d MMM', 'id_ID').format(firstDayThisMonth);
                  final fmtEnd = DateFormat('d MMM yyyy', 'id_ID').format(now);
                  _applyDateFilter(firstDayThisMonth, now, 'Bulan Ini ($fmtStart - $fmtEnd)');
                },
              ),

              // 2. 7 Hari Terakhir
              _buildPeriodOption(
                sheetCtx,
                label: '7 Hari Terakhir',
                sublabel: '${DateFormat('d MMM yyyy', 'id_ID').format(now.subtract(const Duration(days: 7)))} - ${DateFormat('d MMM yyyy', 'id_ID').format(now)}',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final start = now.subtract(const Duration(days: 7));
                  _applyDateFilter(start, now, '7 Hari Terakhir');
                },
              ),

              // 3. 30 Hari Terakhir
              _buildPeriodOption(
                sheetCtx,
                label: '30 Hari Terakhir',
                sublabel: '${DateFormat('d MMM yyyy', 'id_ID').format(now.subtract(const Duration(days: 30)))} - ${DateFormat('d MMM yyyy', 'id_ID').format(now)}',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final start = now.subtract(const Duration(days: 30));
                  _applyDateFilter(start, now, '30 Hari Terakhir');
                },
              ),

              // 4. Bulan Lalu
              _buildPeriodOption(
                sheetCtx,
                label: 'Bulan Lalu (${DateFormat('MMMM yyyy', 'id_ID').format(lastDayLastMonth)})',
                sublabel: '${DateFormat('d MMM yyyy', 'id_ID').format(firstDayLastMonth)} - ${DateFormat('d MMM yyyy', 'id_ID').format(lastDayLastMonth)}',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _applyDateFilter(
                    firstDayLastMonth,
                    lastDayLastMonth,
                    DateFormat('MMMM yyyy', 'id_ID').format(lastDayLastMonth),
                  );
                },
              ),

              const SizedBox(height: 10),

              // 5. Custom Date Range Picker
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _pickCustomDateRange();
                  },
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    'Pilih Tanggal Tertentu (Maks. 31 Hari)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryNavy,
                    side: const BorderSide(color: royalBlue),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodOption(
    BuildContext sheetCtx, {
    required String label,
    required String sublabel,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: const Icon(Icons.calendar_today_rounded, color: primaryNavy, size: 18),
        ),
        title: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        subtitle: Text(
          sublabel,
          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: textMuted, size: 18),
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
        automaticallyImplyLeading: !widget.isTab,
        leading: widget.isTab
            ? null
            : IconButton(
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
            final allMutations = _filteredMutations ?? state.mutations;

            return Column(
              children: [
                const SizedBox(height: 8),

                // 1. Date Filter Bar (Max 31 days period)
                _buildDateFilterBar(),

                // 2. Summary Card (Uang Masuk / Keluar)
                _buildSummaryCard(allMutations),

                // 3. Pill Filter Segmented Tabs (Semua, Uang Masuk, Uang Keluar)
                _buildPillTabBar(),

                // 4. Mutations List Tabs
                Expanded(
                  child: _isFilterLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: primaryNavy),
                          ),
                        )
                      : TabBarView(
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

  // ==================== DATE FILTER BAR ====================
  Widget _buildDateFilterBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.date_range_rounded, size: 20, color: royalBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Periode Mutasi (Maks. 31 Hari)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _periodLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: titleDark,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: _showDateFilterBottomSheet,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  Text(
                    'Ubah',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: royalBlue,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.tune_rounded, size: 14, color: royalBlue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SUMMARY HEADER CARD ====================
  Widget _buildSummaryCard(List<MutationModel> list) {
    double totalCredit = 0;
    double totalDebit = 0;
    for (final m in list) {
      if (m.isCredit) {
        totalCredit += m.amount;
      } else {
        totalDebit += m.amount;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_downward_rounded, size: 13, color: dmbGreen),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Uang Masuk', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: textMuted)),
                      Text(
                        CurrencyFormatter.formatRupiah(totalCredit),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: dmbGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 24, width: 1, color: borderLight),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_upward_rounded, size: 13, color: dmbRed),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Uang Keluar', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: textMuted)),
                      Text(
                        CurrencyFormatter.formatRupiah(totalDebit),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: dmbRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
        onRefresh: () async {
          if (_isCustomFilterApplied) {
            await _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true);
          } else {
            await context.read<AccountCubit>().refresh();
          }
        },
        color: primaryNavy,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 50),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.receipt_long_outlined, size: 34, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Belum Ada Transaksi',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: titleDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Tidak ada riwayat transaksi pada periode $_periodLabel.\nSilakan ubah rentang tanggal untuk melihat periode lainnya.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryNavy,
                        side: const BorderSide(color: royalBlue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: _showDateFilterBottomSheet,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: Text(
                        'Ubah Periode Tanggal',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (_isCustomFilterApplied) {
          await _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true);
        } else {
          await context.read<AccountCubit>().refresh();
        }
      },
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
