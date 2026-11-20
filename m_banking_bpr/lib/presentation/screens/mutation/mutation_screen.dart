import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/mutation_model.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../widgets/app_validation_feedback.dart';

class MutationScreen extends StatefulWidget {
  final bool isTab;
  const MutationScreen({super.key, this.isTab = false});

  @override
  State<MutationScreen> createState() => _MutationScreenState();
}

class _MutationScreenState extends State<MutationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  late DateTime _startDate;
  late DateTime _endDate;
  late String _periodLabel;
  List<MutationModel>? _filteredMutations;
  bool _isFilterLoading = false;
  String? _filterError;

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color dmbRed = AppColors.danger;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true);
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

  Future<void> _applyDateFilter(
    DateTime start,
    DateTime end,
    String label, {
    bool silent = false,
  }) async {
    setState(() {
      _isFilterLoading = true;
      _filterError = null;
      _startDate = start;
      _endDate = end;
      _periodLabel = label;
    });

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
          AppToast.showInfo(
            context,
            'Menampilkan ${results.length} mutasi untuk periode $label',
            title: 'Periode Mutasi',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.humanize(
          e,
          fallback: 'Riwayat mutasi belum dapat dimuat. Silakan coba kembali.',
        );
        setState(() {
          _isFilterLoading = false;
          _filterError = msg;
        });
        if (!silent) {
          AppToast.showError(context, msg, title: 'Gagal Memuat Mutasi');
        }
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
        if (mounted) {
          AppToast.showWarning(
            context,
            'Rentang tanggal maksimal 31 hari per pencarian mutasi.',
            title: 'Rentang Tanggal',
          );
        }
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
                      color: AppColors.primaryLight,
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

              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: m.isCredit ? AppColors.successLight : AppColors.dangerLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: m.isCredit ? AppColors.successBorder : AppColors.dangerBorder,
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
      backgroundColor: const Color(0xFFF6F6F2),
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<AccountCubit, AccountState>(
          builder: (context, state) {
            if (state is AccountLoading && _filteredMutations == null) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF0A2A66)));
            }

            if (state is AccountError && _filteredMutations == null) {
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
                          backgroundColor: const Color(0xFF0A2A66),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: () {
                          context.read<AccountCubit>().refresh();
                          _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true);
                        },
                        child: Text(
                          'Coba Lagi',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final baseMutations = _filteredMutations ?? (state is AccountLoaded ? state.mutations : <MutationModel>[]);
            final activeTabMutations = _filterMutations(baseMutations, _selectedTabIndex);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  child: Row(
                    children: [
                      if (!widget.isTab) ...[
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 17,
                                color: titleDark,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Text(
                          'Mutasi Tabungan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                _buildPillTabBar(),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _showDateFilterBottomSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 15,
                              color: Color(0xFF0A2A66),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _periodLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: titleDark,
                                ),
                              ),
                            ),
                            Text(
                              'Ubah',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0A2A66),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Color(0xFF0A2A66),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                _buildSummaryCard(activeTabMutations),

                const SizedBox(height: 14),

                Expanded(
                  child: _isFilterLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: Color(0xFF0A2A66)),
                          ),
                        )
                      : _filterError != null && _filteredMutations == null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.cloud_off_rounded, size: 44, color: textMuted),
                                    const SizedBox(height: 12),
                                    Text(
                                      _filterError!,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: titleDark,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    ElevatedButton.icon(
                                      onPressed: () => _applyDateFilter(_startDate, _endDate, _periodLabel),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0A2A66),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(140, 44),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(Icons.refresh_rounded, size: 16),
                                      label: const Text('Coba Lagi'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _buildMutationList(baseMutations),
                                _buildMutationList(_filterMutations(baseMutations, 1)),
                                _buildMutationList(_filterMutations(baseMutations, 2)),
                              ],
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCard(List<MutationModel> list) {
    var totalCredit = const Money.zero();
    var totalDebit = const Money.zero();
    for (final m in list) {
      if (m.isCredit) {
        totalCredit += m.amount;
      } else {
        totalDebit += m.amount;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uang masuk',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+ ${CurrencyFormatter.formatRupiah(totalCredit)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F9D76),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uang keluar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '- ${CurrencyFormatter.formatRupiah(totalDebit)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: dmbRed,
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

  Widget _buildPillTabBar() {
    final tabs = ['Semua', 'Masuk', 'Keluar'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () {
                _tabController.animateTo(index);
                setState(() => _selectedTabIndex = index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0A2A66) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: isSelected
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Text(
                  tabs[index],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : titleDark,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMutationList(List<MutationModel> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true),
        color: const Color(0xFF0A2A66),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.receipt_long_outlined, size: 32, color: Color(0xFF94A3B8)),
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
                        foregroundColor: const Color(0xFF0A2A66),
                        side: const BorderSide(color: Color(0xFF0A2A66)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: _showDateFilterBottomSheet,
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
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
      onRefresh: () => _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true),
      color: const Color(0xFF0A2A66),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: List.generate(items.length, (index) {
                final m = items[index];
                final isLast = index == items.length - 1;
                return Column(
                  children: [
                    InkWell(
                      onTap: () => _showTransactionReceipt(context, m),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: m.isCredit
                                    ? const Color(0xFFDDF7EC)
                                    : const Color(0xFFEBF2FF),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  m.isCredit
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  color: m.isCredit
                                      ? const Color(0xFF0F9D76)
                                      : const Color(0xFF0A2A66),
                                  size: 19,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: titleDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    CurrencyFormatter.formatDate(m.createdAt),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      color: textMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              (m.isCredit ? '+ ' : '- ') +
                                  CurrencyFormatter.formatRupiah(m.amount),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: m.isCredit ? const Color(0xFF0F9D76) : dmbRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
