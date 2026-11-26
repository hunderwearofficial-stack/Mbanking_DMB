import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/mutation_model.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import '../../widgets/mutation_truncated_notice.dart';

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
  bool _filterHasMore = false;
  bool _isFilterLoading = false;
  String? _filterError;
  List<Map<String, dynamic>> _savingsAccounts = [];
  List<Map<String, dynamic>> _depositAccounts = [];
  List<Map<String, dynamic>> _loanAccounts = [];
  int _selectedCategory = 0; // 0: Tabungan, 1: Deposito, 2: Pinjaman
  String? _selectedAccountNumber;

  List<Map<String, dynamic>> get _accounts {
    if (_selectedCategory == 1) return _depositAccounts;
    if (_selectedCategory == 2) return _loanAccounts;
    return _savingsAccounts;
  }

  String get _categoryLabel {
    if (_selectedCategory == 1) return 'Deposito';
    if (_selectedCategory == 2) return 'Pinjaman';
    return 'Tabungan';
  }

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color dmbRed = AppColors.danger;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;

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
        final accountState = context.read<AccountCubit>().state;
        if (accountState is AccountLoaded && accountState.account.accountNumber.isNotEmpty) {
          _selectedAccountNumber = accountState.account.accountNumber;
        }
        _loadAccounts();
        _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true);
      }
    });
  }

  Future<void> _loadAccounts() async {
    try {
      final repo = context.read<AccountCubit>().accountRepository;
      final results = await Future.wait([
        repo.getSavingsAccounts().catchError((_) => <Map<String, dynamic>>[]),
        repo.getDeposits().catchError((_) => <Map<String, dynamic>>[]),
        repo.getLoans().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _savingsAccounts = results[0];
        _depositAccounts = results[1];
        _loanAccounts = results[2];
        if ((_selectedAccountNumber == null || _selectedAccountNumber!.isEmpty) &&
            _accounts.isNotEmpty) {
          final first = _extractAccountNo(_accounts.first);
          if (first.isNotEmpty) _selectedAccountNumber = first;
        }
      });
    } catch (_) {}
  }

  String _extractAccountNo(Map<String, dynamic> item) {
    return (item['nomor_rekening'] ?? item['account_number'] ?? '').toString().trim();
  }

  String _extractProductName(Map<String, dynamic> item) {
    final name = (item['nama_produk'] ?? item['produk_tabungan'] ?? item['account_type'] ?? '').toString().trim();
    return name.isNotEmpty ? name : 'Tabungan Bank DMB';
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
      String? accNo = _selectedAccountNumber;
      if (_selectedCategory == 0 &&
          (accNo == null || accNo.isEmpty) &&
          accountState is AccountLoaded) {
        accNo = accountState.account.accountNumber;
      }

      if (_selectedCategory != 0 && (accNo == null || accNo.isEmpty)) {
        if (mounted) {
          setState(() {
            _filteredMutations = [];
            _filterHasMore = false;
            _isFilterLoading = false;
          });
        }
        return;
      }

      final page = _selectedCategory == 1
          ? await repo.getDepositMutationsPage(
              accNo!,
              limit: 100,
              startDate: sStr,
              endDate: eStr,
            )
          : _selectedCategory == 2
              ? await repo.getLoanMutationsPage(
                  accNo!,
                  limit: 100,
                  startDate: sStr,
                  endDate: eStr,
                )
              : await repo.getMutationsPage(
                  limit: 100,
                  accountNumber: accNo,
                  startDate: sStr,
                  endDate: eStr,
                );
      final results = page.items;

      if (mounted) {
        setState(() {
          _filteredMutations = results;
          _filterHasMore = page.hasMore;
          _isFilterLoading = false;
        });
        if (!silent) {
          AppToast.showInfo(
            context,
            page.hasMore
                ? 'Menampilkan ${results.length} mutasi terbaru periode $label. Masih ada transaksi lain; persempit rentang tanggal.'
                : 'Menampilkan ${results.length} mutasi untuk periode $label',
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
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: m.isCredit ? const Color(0xFFD1FAE5) : AuthUiTokens.softBlueBg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.check_rounded,
                      color: m.isCredit ? const Color(0xFF059669) : AuthUiTokens.deepCobalt,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Center(
                child: Text(
                  'Transaksi Berhasil',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AuthUiTokens.titleDark,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  CurrencyFormatter.formatDate(m.createdAt),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: AuthUiTokens.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AuthUiTokens.canvas,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8EEF6)),
                ),
                child: Column(
                  children: [
                    _buildReceiptRow(
                      'Jenis Transaksi',
                      m.isCredit ? 'Dana Masuk (Kredit)' : 'Dana Keluar (Debit)',
                    ),
                    _buildReceiptRow(
                      'Nominal',
                      (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                      valueColor: m.isCredit ? const Color(0xFF059669) : dmbRed,
                    ),
                    _buildReceiptRow('Keterangan', m.description),
                    _buildReceiptRow('Nomor Referensi', m.referenceNumber),
                    _buildReceiptRow('Nomor Rekening', m.accountNumber),
                    _buildReceiptRow('Saldo Setelahnya', CurrencyFormatter.formatRupiah(m.balanceAfter)),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AuthUiTokens.deepCobalt,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(modalCtx),
                  child: Text(
                    'Kembali',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
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

  Widget _buildReceiptRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AuthUiTokens.titleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: BlocBuilder<AccountCubit, AccountState>(
          builder: (context, state) {
            if (state is AccountLoading && _filteredMutations == null) {
              return const Center(
                child: CircularProgressIndicator(color: AuthUiTokens.deepCobalt),
              );
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
                          backgroundColor: AuthUiTokens.deepCobalt,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: Row(
                    children: [
                      if (!widget.isTab) ...[
                        Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AuthUiTokens.inputBorder),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 17,
                                color: AuthUiTokens.deepCobalt,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          'Riwayat Transaksi',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AuthUiTokens.titleDark,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _showDateFilterBottomSheet,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AuthUiTokens.inputBorder),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              size: 19,
                              color: AuthUiTokens.deepCobalt,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                _buildAccountSelector(state),

                _buildPillTabBar(),

                const SizedBox(height: 12),

                _buildSummaryCard(activeTabMutations),

                const SizedBox(height: 12),

                Expanded(
                  child: _isFilterLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: AuthUiTokens.deepCobalt),
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
                                        backgroundColor: AuthUiTokens.deepCobalt,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(140, 44),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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

  Widget _buildAccountSelector(AccountState state) {
    String accNo = _selectedAccountNumber ?? '';
    String productName = '$_categoryLabel Bank DMB';

    if (_selectedCategory == 0 && accNo.isEmpty && state is AccountLoaded) {
      accNo = state.account.accountNumber;
      if (state.account.accountType.trim().isNotEmpty && state.account.accountType.trim() != '-') {
        productName = state.account.accountType.trim();
      }
    }
    for (final a in _accounts) {
      if (_extractAccountNo(a) == accNo) {
        productName = _extractProductName(a);
        break;
      }
    }

    final canSwitch = _accounts.length > 1;
    final displayAcc = accNo.isNotEmpty ? accNo : 'Belum ada rekening $_categoryLabel';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(
        children: [
          // Category Switcher: Tabungan | Deposito | Pinjaman
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EEF6)),
            ),
            child: Row(
              children: [
                _buildCategoryPill(0, 'Tabungan', _savingsAccounts.length),
                _buildCategoryPill(1, 'Deposito', _depositAccounts.length),
                _buildCategoryPill(2, 'Pinjaman', _loanAccounts.length),
              ],
            ),
          ),
          if (accNo.isNotEmpty || _accounts.isNotEmpty)
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: canSwitch ? _showAccountPickerSheet : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8EEF6)),
                    boxShadow: [
                      BoxShadow(
                        color: AuthUiTokens.royalBlue.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AuthUiTokens.softBlueBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 17,
                    color: AuthUiTokens.deepCobalt,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AuthUiTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Rek. $displayAcc',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AuthUiTokens.titleDark,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canSwitch)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AuthUiTokens.softBlueBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pilih',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AuthUiTokens.deepCobalt,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AuthUiTokens.deepCobalt,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  Widget _buildCategoryPill(int index, String label, int count) {
    final isSelected = _selectedCategory == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_selectedCategory == index) return;
          setState(() {
            _selectedCategory = index;
            _selectedAccountNumber = _accounts.isNotEmpty ? _extractAccountNo(_accounts.first) : null;
          });
          _applyDateFilter(_startDate, _endDate, _periodLabel, silent: true);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? primaryNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            count > 0 ? '$label ($count)' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : textMuted,
            ),
          ),
        ),
      ),
    );
  }

  void _showAccountPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                  decoration: BoxDecoration(
                    color: borderLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pilih Rekening $_categoryLabel',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: AuthUiTokens.titleDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mutasi akan ditampilkan sesuai rekening yang dipilih',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AuthUiTokens.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _accounts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final item = _accounts[i];
                    final acc = _extractAccountNo(item);
                    final prod = _extractProductName(item);
                    final bal = Money.tryParse(item['saldo'] ?? item['nominal'] ?? item['baki_debet'] ?? item['balance']);
                    final selected = acc == _selectedAccountNumber;
                    return Material(
                      color: selected ? AuthUiTokens.softBlueBg : AuthUiTokens.canvas,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          if (acc.isNotEmpty && acc != _selectedAccountNumber) {
                            setState(() => _selectedAccountNumber = acc);
                            _applyDateFilter(_startDate, _endDate, _periodLabel);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? AuthUiTokens.royalBlue
                                  : const Color(0xFFE2E8F0),
                              width: selected ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: selected ? AuthUiTokens.deepCobalt : Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.account_balance_wallet_rounded,
                                  size: 19,
                                  color: selected ? Colors.white : AuthUiTokens.deepCobalt,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prod,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: AuthUiTokens.titleDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'No. Rek $acc${bal != null ? ' • ${CurrencyFormatter.formatRupiah(bal)}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AuthUiTokens.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AuthUiTokens.deepCobalt,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
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
    final totalAll = totalCredit + totalDebit;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: AuthUiTokens.royalBlue.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Mutasi',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AuthUiTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.formatRupiah(totalAll),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AuthUiTokens.titleDark,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AuthUiTokens.softBlueBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AuthUiTokens.softBlueBorder),
                  ),
                  child: const CustomPaint(
                    painter: _MiniMutasiChartPainter(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF059669),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Masuk: +${CurrencyFormatter.formatRupiah(totalCredit)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: dmbRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Keluar: -${CurrencyFormatter.formatRupiah(totalDebit)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: dmbRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillTabBar() {
    final tabs = ['Semua', 'Masuk', 'Keluar'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          ...List.generate(tabs.length, (index) {
            final isSelected = _selectedTabIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  _tabController.animateTo(index);
                  setState(() => _selectedTabIndex = index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AuthUiTokens.deepCobalt : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    tabs[index],
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AuthUiTokens.titleDark,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          GestureDetector(
            onTap: _showDateFilterBottomSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AuthUiTokens.softBlueBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AuthUiTokens.softBlueBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.date_range_rounded,
                    size: 13,
                    color: AuthUiTokens.deepCobalt,
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 82),
                    child: Text(
                      _periodLabel.split('(').first.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AuthUiTokens.deepCobalt,
                      ),
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
          if (_filterHasMore && _filteredMutations != null)
            MutationTruncatedNotice(shown: _filteredMutations!.length),
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

class _MiniMutasiChartPainter extends CustomPainter {
  const _MiniMutasiChartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final colors = [
      const Color(0xFF7DD3FC),
      const Color(0xFF00C2D1),
      const Color(0xFF118CE0),
      const Color(0xFF033172),
    ];
    final heights = [0.34, 0.54, 0.72, 0.94];
    const barW = 5.5;
    final gap = (w - barW * 4) / 3;

    for (var i = 0; i < 4; i++) {
      final barH = h * heights[i];
      final x = i * (barW + gap);
      final y = h - barH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          const Radius.circular(3),
        ),
        Paint()..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
