import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _MonthPeriod {
  final String title;
  final String subtitle;
  final DateTime startDate;
  final DateTime endDate;

  const _MonthPeriod({
    required this.title,
    required this.subtitle,
    required this.startDate,
    required this.endDate,
  });
}

class EStatementScreen extends StatefulWidget {
  const EStatementScreen({super.key});

  @override
  State<EStatementScreen> createState() => _EStatementScreenState();
}

class _EStatementScreenState extends State<EStatementScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color dmbRed = AppColors.danger;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  static const List<String> _monthNames = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  late final List<_MonthPeriod> _periods;
  int _selectedMonthIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  List<MutationModel> _mutations = [];

  @override
  void initState() {
    super.initState();
    _periods = _buildLastSixMonths();
    _loadMonthMutations();
  }

  List<_MonthPeriod> _buildLastSixMonths() {
    final now = DateTime.now();
    final list = <_MonthPeriod>[];
    for (int i = 0; i < 6; i++) {
      final monthDate = DateTime(now.year, now.month - i, 1);
      final isCurrentMonth = i == 0;
      final endDate = isCurrentMonth
          ? DateTime(now.year, now.month, now.day)
          : DateTime(monthDate.year, monthDate.month + 1, 0);
      final monthTitle = '${_monthNames[monthDate.month - 1]} ${monthDate.year}';
      final fmtStart = DateFormat('d MMM', 'id_ID').format(monthDate);
      final fmtEnd = DateFormat('d MMM yyyy', 'id_ID').format(endDate);
      final subtitle = isCurrentMonth
          ? 'Bulan Berjalan ($fmtStart - $fmtEnd)'
          : 'Periode 1 Bulan Penuh ($fmtStart - $fmtEnd)';

      list.add(_MonthPeriod(
        title: monthTitle,
        subtitle: subtitle,
        startDate: monthDate,
        endDate: endDate,
      ));
    }
    return list;
  }

  Future<void> _loadMonthMutations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final period = _periods[_selectedMonthIndex];
    final startStr = DateFormat('yyyy-MM-dd').format(period.startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(period.endDate);

    try {
      final cubit = context.read<AccountCubit>();
      String? accNo;
      if (cubit.state is AccountLoaded) {
        accNo = (cubit.state as AccountLoaded).account.accountNumber;
      }

      final items = await cubit.accountRepository.getMutations(
        limit: 50,
        accountNumber: accNo,
        startDate: startStr,
        endDate: endStr,
      );

      if (!mounted) return;
      setState(() {
        _mutations = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ApiException.humanize(
          e,
          fallback: 'Ringkasan mutasi bulanan belum dapat dimuat. Silakan coba kembali.',
        );
        _isLoading = false;
      });
    }
  }

  void _copyStatementSummary(_MonthPeriod period, Money totalCredit, Money totalDebit, Money? closingBalance) {
    final bankName = DynamicConfigService().config.bankName;
    final accState = context.read<AccountCubit>().state;
    final accNo = accState is AccountLoaded ? accState.account.accountNumber : '-';
    final summary = '''
RINGKASAN MUTASI BULANAN (e-Statement)
$bankName
Periode: ${period.title} (${period.subtitle})
No. Rekening: $accNo
Total Uang Masuk (CR): ${CurrencyFormatter.formatRupiah(totalCredit)}
Total Uang Keluar (DB): ${CurrencyFormatter.formatRupiah(totalDebit)}
Jumlah Transaksi: ${_mutations.length} transaksi
Saldo Akhir Tercatat: ${CurrencyFormatter.formatRupiah(closingBalance)}
'''.trim();

    Clipboard.setData(ClipboardData(text: summary));
    AppToast.showSuccess(
      context,
      'Ringkasan e-Statement ${period.title} berhasil disalin ke papan klip.',
      title: 'Ringkasan Disalin',
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPeriod = _periods[_selectedMonthIndex];

    var totalCredit = const Money.zero();
    var totalDebit = const Money.zero();
    for (final m in _mutations) {
      if (m.isCredit) {
        totalCredit += m.amount;
      } else {
        totalDebit += m.amount;
      }
    }

    final accState = context.watch<AccountCubit>().state;
    String accNum = '-';
    String accType = 'Tabungan Bank DMB';
    Money? currentBalance;

    if (accState is AccountLoaded) {
      accNum = accState.account.accountNumber.isNotEmpty ? accState.account.accountNumber : '-';
      accType = accState.account.accountType.isNotEmpty ? accState.account.accountType : 'Tabungan Bank DMB';
      currentBalance = accState.account.balance;
    }

    final Money? closingBalance = _mutations.isNotEmpty ? _mutations.first.balanceAfter : currentBalance;

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
              'e-Statement Rekening',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'RINGKASAN MUTASI BULANAN',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: royalBlue,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20, color: titleDark),
            onPressed: _loadMonthMutations,
            tooltip: 'Perbarui Data',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMonthMutations,
        color: primaryNavy,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryNavy,
                      royalBlue,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: royalBlue.withOpacity(0.24),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ringkasan Mutasi Bulanan',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pantau rekapitulasi arus kas masuk, keluar, dan rincian transaksi bulanan rekening Anda secara langsung.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: Colors.white.withOpacity(0.88),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.analytics_outlined, color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Rekening Sumber',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: royalBlue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            accType,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'No. Rek: $accNum',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      CurrencyFormatter.formatRupiah(currentBalance),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: primaryNavy,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Pilih Periode Bulan (6 Bulan Terakhir)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _periods.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isSelected = _selectedMonthIndex == index;
                    final p = _periods[index];
                    return ChoiceChip(
                      label: Text(
                        p.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : titleDark,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: primaryNavy,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: isSelected ? primaryNavy : borderLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (selected) {
                        if (selected && _selectedMonthIndex != index) {
                          setState(() => _selectedMonthIndex = index);
                          _loadMonthMutations();
                        }
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rekapitulasi ${selectedPeriod.title}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selectedPeriod.subtitle,
                              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                            ),
                          ],
                        ),
                        if (!_isLoading && _errorMessage == null)
                          InkWell(
                            onTap: () => _copyStatementSummary(
                              selectedPeriod,
                              totalCredit,
                              totalDebit,
                              closingBalance,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.primaryBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.copy_rounded, size: 13, color: royalBlue),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Salin Ringkasan',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: royalBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: borderLight),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.successBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.arrow_downward_rounded, size: 14, color: dmbGreen),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Total Uang Masuk',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: dmbGreen,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  CurrencyFormatter.formatRupiah(totalCredit),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: titleDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.dangerLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.dangerBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.arrow_upward_rounded, size: 14, color: dmbRed),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Total Uang Keluar',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: dmbRed,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  CurrencyFormatter.formatRupiah(totalDebit),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: titleDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Jumlah Aktivitas Transaksi:',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                        ),
                        Text(
                          '${_mutations.length} Transaksi',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Saldo Akhir Periode:',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                        ),
                        Text(
                          CurrencyFormatter.formatRupiah(closingBalance),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: primaryNavy,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Rincian Transaksi (${selectedPeriod.title})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 10),

              if (_isLoading)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderLight),
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: primaryNavy),
                      const SizedBox(height: 14),
                      Text(
                        'Memuat mutasi periode ${selectedPeriod.title}...',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted),
                      ),
                    ],
                  ),
                )
              else if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderLight),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 42, color: textMuted),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: titleDark,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _loadMonthMutations,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryNavy,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(140, 42),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                )
              else if (_mutations.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderLight),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.receipt_long_outlined, size: 30, color: textMuted),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tidak Ada Mutasi pada ${selectedPeriod.title}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: titleDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Belum ada transaksi uang masuk atau keluar yang tercatat pada periode bulan ini.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, height: 1.4),
                      ),
                    ],
                  ),
                )
              else
                ..._mutations.map((m) => _buildMutationTile(m)),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: royalBlue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ringkasan mutasi elektronik ini disajikan langsung dari catatan transaksi resmi ${DynamicConfigService().config.bankName}.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMutationTile(MutationModel m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: m.isCredit ? AppColors.successLight : AppColors.dangerLight,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                m.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: m.isCredit ? dmbGreen : dmbRed,
                size: 18,
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
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: titleDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.formatDate(m.createdAt),
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Saldo: ${CurrencyFormatter.formatRupiah(m.balanceAfter)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: m.isCredit ? dmbGreen : dmbRed,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: m.isCredit ? AppColors.successLight : AppColors.dangerLight,
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
    );
  }
}
