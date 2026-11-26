import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import '../helpdesk/helpdesk_screen.dart';
import 'loan_application_bottom_sheet.dart';
import 'loan_detail_screen.dart';
import 'loan_kkm_detail_screen.dart';

class LoanScreen extends StatefulWidget {
  const LoanScreen({super.key});

  @override
  State<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends State<LoanScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _loans = [];
  List<LoanKkmBundle> _kkmLoans = [];
  List<Map<String, dynamic>> _regularLoans = [];
  final Map<String, Map<String, dynamic>> _detailsByAcc = {};
  String _customerName = '';

  @override
  void initState() {
    super.initState();
    _fetchLoanData();
  }

  Future<void> _fetchLoanData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authState = context.read<AuthCubit>().state;
      String? cif;
      String holderName = '';
      if (authState is AuthAuthenticated) {
        cif = authState.user.cif;
        holderName = authState.user.fullName;
      }
      if (cif == null || cif.isEmpty) {
        final storage = context.read<AuthCubit>().authRepository.secureStorage;
        cif = await storage.getCIF();
      }
      if (cif == null || cif.isEmpty) {
        if (mounted) {
          setState(() {
            _loans = [];
            _kkmLoans = [];
            _regularLoans = [];
            _isLoading = false;
          });
        }
        return;
      }

      if (!mounted) return;
      final repo = context.read<AccountRepository>();
      final loans = await repo.getLoans(cifNumber: cif);

      final List<LoanKkmBundle> kkmList = [];
      final List<Map<String, dynamic>> regularList = [];
      final Map<String, Map<String, dynamic>> detailsMap = {};

      await Future.wait(loans.map((loan) async {
        final accNo = (loan['nomor_rekening'] ?? '').toString().trim();
        Map<String, dynamic>? detail;
        if (accNo.isNotEmpty) {
          try {
            detail = await repo.getLoanDetail(accNo, cifNumber: cif);
          } catch (_) {}
        }
        if (detail != null && accNo.isNotEmpty) {
          detailsMap[accNo] = detail;
        }
        final jenisKkm = detail?['jenis_kkm']?.toString().trim().toLowerCase();
        if (jenisKkm != null && jenisKkm.isNotEmpty && jenisKkm != 'null' && accNo.isNotEmpty) {
          try {
            final kkm = await repo.getLoanKKM(accNo);
            if (kkm != null) {
              kkmList.add(LoanKkmBundle(account: loan, detail: detail!, kkm: kkm));
              return;
            }
          } catch (_) {}
        }
        regularList.add(loan);
      }));

      if (mounted) {
        setState(() {
          _customerName = holderName;
          _loans = loans;
          _kkmLoans = kkmList;
          _regularLoans = regularList;
          _detailsByAcc
            ..clear()
            ..addAll(detailsMap);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiException.humanize(
            e,
            fallback: 'Layanan sedang mengalami gangguan. Silakan coba kembali beberapa saat lagi.',
          );
          _isLoading = false;
        });
      }
    }
  }

  void _showToast(String message) {
    AppToast.showSuccess(context, message);
  }

  String _field(Map<String, dynamic> item, List<String> keys) {
    for (final k in keys) {
      final v = item[k];
      if (v != null && v.toString().trim().isNotEmpty && v.toString().trim() != 'null') {
        return v.toString();
      }
    }
    return '-';
  }

  void _showLoanDetailSheet(BuildContext context, Map<String, dynamic> initialLoan) {
    final accNo = initialLoan['nomor_rekening']?.toString() ?? '-';
    final repo = context.read<AccountRepository>();
    final Future<Map<String, dynamic>?> detailFuture = (accNo != '-' && accNo.isNotEmpty)
        ? repo.getLoanDetail(accNo).catchError((_) => null)
        : Future.value(null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => FutureBuilder<Map<String, dynamic>?>(
        future: detailFuture,
        builder: (ctx, snapshot) {
          final loan = {
            ...initialLoan,
            if (snapshot.data != null) ...snapshot.data!,
          };
          final isLoadingDetail = snapshot.connectionState == ConnectionState.waiting;
          final prodName = _field(loan, ['nama_produk', 'produk']);
          final plafon = Money.tryParse(loan['plafon']);
          final bakiDebet = Money.tryParse(loan['baki_debet']);
          final pokokTerbayar = (plafon != null && bakiDebet != null && plafon >= bakiDebet) ? plafon - bakiDebet : null;
          final statusKet = _field(loan, ['status_rekening_keterangan', 'status']);
          final kolKet = _field(loan, ['kolektibilitas_keterangan']);
          final kolNo = loan['kolektibilitas'];
          final kolLabel = kolNo != null ? '$kolKet (Kol $kolNo)' : kolKet;
          final isLancar = kolNo == 1 || kolKet.toLowerCase().contains('lancar');
          final rateVal = loan['suku_bunga_tahunan'] ?? loan['suku_bunga'];
          final rate = rateVal != null && rateVal.toString().isNotEmpty ? '$rateVal% p.a.' : null;
          final jatuhTempo = _field(loan, ['tanggal_jatuh_tempo', 'tgl_jatuh_tempo']);

          return SafeArea(
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
                      decoration: BoxDecoration(
                        color: borderLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prodName,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'No. Rekening: $accNo',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.successBorder),
                        ),
                        child: Text(
                          statusKet.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: dmbGreen,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (isLoadingDetail) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(
                      minHeight: 2,
                      color: royalBlue,
                      backgroundColor: borderLight,
                    ),
                  ],

                  const SizedBox(height: 18),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 14),

                  _buildDetailRow('Plafon Pinjaman', CurrencyFormatter.formatRupiah(plafon)),
                  _buildDetailRow('Sisa Pokok (Baki Debet)', CurrencyFormatter.formatRupiah(bakiDebet), isBold: true),
                  _buildDetailRow('Pokok Terbayar', CurrencyFormatter.formatRupiah(pokokTerbayar)),
                  if (rate != null) _buildDetailRow('Suku Bunga', rate),
                  if (jatuhTempo != '-') _buildDetailRow('Tanggal Jatuh Tempo', jatuhTempo),
                  _buildDetailRow('Status Kolektibilitas', kolLabel, isGreen: isLancar),
                  _buildDetailRow('Kantor Pelayanan', _field(loan, ['nama_kantor', 'kantor'])),

                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                        );
                      },
                      icon: const Icon(Icons.support_agent_rounded, size: 20),
                      label: Text(
                        'Konsultasi Petugas Kredit (AO)',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
                color: isGreen ? dmbGreen : titleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && _errorMessage == null && _kkmLoans.isNotEmpty) {
      return _buildKkmOverviewScaffold();
    }
    final bankName = DynamicConfigService().config.bankName.toUpperCase();
    Money? totalPlafon = const Money.zero();
    Money? totalBakiDebet = const Money.zero();
    for (final loan in _loans) {
      final p = Money.tryParse(loan['plafon']);
      final b = Money.tryParse(loan['baki_debet']);
      totalPlafon = (totalPlafon == null || p == null) ? null : totalPlafon + p;
      totalBakiDebet = (totalBakiDebet == null || b == null) ? null : totalBakiDebet + b;
    }

    double progress = 0.0;
    if (totalPlafon != null && totalBakiDebet != null && !totalPlafon.isZero) {
      progress = (totalPlafon - totalBakiDebet).ratioOf(totalPlafon);
    }

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Row(
                children: [
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
                  Expanded(
                    child: Text(
                      'Fasilitas Pinjaman',
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
                      onTap: _fetchLoanData,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AuthUiTokens.inputBorder),
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          size: 19,
                          color: AuthUiTokens.deepCobalt,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchLoanData,
                color: AuthUiTokens.deepCobalt,
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AuthUiTokens.deepCobalt),
                            SizedBox(height: 16),
                            Text('Memuat data fasilitas pinjaman...', style: TextStyle(color: textMuted)),
                  ],
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 48, color: textMuted),
                          const SizedBox(height: 14),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: titleDark),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _fetchLoanData,
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _loans.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primaryBorder),
                                ),
                                child: const Icon(Icons.credit_score_outlined, color: royalBlue, size: 36),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Belum Ada Fasilitas Pinjaman',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: titleDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Anda belum memiliki pinjaman aktif di Bank DMB. Ajukan pinjaman modal kerja atau kredit mikro dengan bunga kompetitif.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted, height: 1.45),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryNavy,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                                ),
                                onPressed: () => LoanApplicationBottomSheet.show(context, onSuccess: _fetchLoanData),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(
                                  'Ajukan Fasilitas Kredit Baru',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryNavy,
                                  side: const BorderSide(color: borderLight),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                                  );
                                },
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                label: Text(
                                  'Konsultasi CS',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: const Color(0xFF033172),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF033172).withOpacity(0.20),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_loans.length} Fasilitas Aktif • $bankName',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withOpacity(0.82),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.16),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'DIAWASI OJK',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Sisa pokok',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withOpacity(0.78),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CurrencyFormatter.formatRupiah(totalBakiDebet),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 8,
                                      backgroundColor: Colors.white.withOpacity(0.18),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total Plafon: ${CurrencyFormatter.formatRupiah(totalPlafon)}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: Colors.white.withOpacity(0.85),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${(progress * 100).toStringAsFixed(1)}% Lunas',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF34D399),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 22),

                            Text(
                              'Daftar Pinjaman',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF033172),
                              ),
                            ),
                            const SizedBox(height: 12),

                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _loans.length,
                              itemBuilder: (context, index) {
                                final loan = _loans[index];
                                final rawAccNo = loan['nomor_rekening']?.toString() ?? '-';
                                final canCopyAcc = rawAccNo.isNotEmpty && rawAccNo != '-';
                                final formattedAcc = _formatAccountNumber(rawAccNo);
                                final productName = loan['nama_produk']?.toString() ?? '-';
                                final plafon = Money.tryParse(loan['plafon']);
                                final bakiDebet = Money.tryParse(loan['baki_debet']);
                                final statusKet = loan['status_rekening_keterangan']?.toString() ?? '-';
                                final kolKet = loan['kolektibilitas_keterangan']?.toString() ?? '-';

                                double itemProgress = 0.0;
                                if (plafon != null && bakiDebet != null && !plafon.isZero) {
                                  itemProgress = (plafon - bakiDebet).ratioOf(plafon);
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
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
                                    borderRadius: BorderRadius.circular(20),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        final accNo = (loan['nomor_rekening'] ?? '').toString().trim();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => LoanDetailScreen(
                                              initialLoan: loan,
                                              initialDetail: _detailsByAcc[accNo],
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 42,
                                                  height: 42,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEFF6FF),
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  child: const Icon(
                                                    Icons.account_balance_wallet_outlined,
                                                    color: Color(0xFF033172),
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        productName,
                                                        style: GoogleFonts.plusJakartaSans(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w800,
                                                          color: const Color(0xFF033172),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              formattedAcc,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: GoogleFonts.plusJakartaSans(
                                                                fontSize: 12,
                                                                color: textMuted,
                                                                fontWeight: FontWeight.w600,
                                                              ),
                                                            ),
                                                          ),
                                                          if (canCopyAcc) ...[
                                                            const SizedBox(width: 6),
                                                            GestureDetector(
                                                              onTap: () {
                                                                Clipboard.setData(ClipboardData(text: rawAccNo));
                                                                _showToast('Nomor rekening disalin: $rawAccNo');
                                                              },
                                                              child: const Icon(
                                                                Icons.copy_rounded,
                                                                size: 13,
                                                                color: Color(0xFF0550A6),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE6F7F1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    statusKet.toUpperCase(),
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w800,
                                                      color: const Color(0xFF0F9D76),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const Padding(
                                              padding: EdgeInsets.symmetric(vertical: 14),
                                              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                                            ),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Sisa pokok',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 11.5,
                                                        color: textMuted,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      CurrencyFormatter.formatRupiah(bakiDebet),
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w900,
                                                        color: const Color(0xFF033172),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      'Plafon kredit',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 11.5,
                                                        color: textMuted,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      CurrencyFormatter.formatRupiah(plafon),
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w800,
                                                        color: const Color(0xFF033172),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 14),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: LinearProgressIndicator(
                                                value: itemProgress,
                                                minHeight: 6,
                                                backgroundColor: const Color(0xFFF1F5F9),
                                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0F9D76)),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.verified_rounded,
                                                      size: 14,
                                                      color: Color(0xFF0F9D76),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      'Kol: $kolKet',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: const Color(0xFF0F9D76),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    Text(
                                                      'Lihat Rincian',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w700,
                                                        color: const Color(0xFF0550A6),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 2),
                                                    const Icon(
                                                      Icons.chevron_right_rounded,
                                                      size: 16,
                                                      color: Color(0xFF0550A6),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => LoanApplicationBottomSheet.show(context, onSuccess: _fetchLoanData),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF033172),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(
                      'Ajukan Pinjaman',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAccountNumber(String acc) {
    if (acc.length == 16) {
      return '${acc.substring(0, 4)} ${acc.substring(4, 8)} ${acc.substring(8, 12)} ${acc.substring(12)}';
    }
    return acc;
  }

  Widget _buildKkmOverviewScaffold() {
    final firstKkm = _kkmLoans.first.kkm;
    final pertemuan = firstKkm['pertemuan'] is Map
        ? Map<String, dynamic>.from(firstKkm['pertemuan'] as Map)
        : <String, dynamic>{};
    final hari = pertemuan['hari']?.toString() ?? '';
    final tglBerikut = _formatShortDate(pertemuan['tanggal_berikutnya']);
    final jam = pertemuan['jam']?.toString() ?? '';
    final meetingLabel = [
      if (hari.isNotEmpty) hari,
      if (tglBerikut != '-') tglBerikut,
    ].join(' ');
    final meetingFull = meetingLabel.isNotEmpty
        ? 'Pertemuan $meetingLabel${jam.isNotEmpty ? ', $jam' : ''}'
        : 'Jadwal pertemuan belum tersedia';

    Money totalHarusDibayar = Money.zero();
    bool allSudahSetor = true;
    int totalTunggakKali = 0;
    Money totalTunggakNominal = Money.zero();
    String? vaNumber;

    for (final b in _kkmLoans) {
      final mIni = b.kkm['minggu_ini'] is Map
          ? Map<String, dynamic>.from(b.kkm['minggu_ini'] as Map)
          : <String, dynamic>{};
      final setoran = b.kkm['setoran'] is Map
          ? Map<String, dynamic>.from(b.kkm['setoran'] as Map)
          : <String, dynamic>{};
      final tunggakan = setoran['tunggakan'] is Map
          ? Map<String, dynamic>.from(setoran['tunggakan'] as Map)
          : <String, dynamic>{};

      final harus = Money.tryParse(mIni['harus_dibayar']) ?? Money.zero();
      totalHarusDibayar = totalHarusDibayar + harus;
      if (mIni['sudah_setor'] != true && !harus.isZero) {
        allSudahSetor = false;
      }
      totalTunggakKali += int.tryParse((tunggakan['kali'] ?? '0').toString()) ?? 0;
      totalTunggakNominal = totalTunggakNominal + (Money.tryParse(tunggakan['nominal']) ?? Money.zero());

      final candVa = b.detail['virtual_account']?.toString().trim();
      if (vaNumber == null && candVa != null && candVa.isNotEmpty && candVa != 'null') {
        vaNumber = candVa;
      }
    }

    final displayName = _customerName.trim().isNotEmpty ? _customerName.trim() : 'Nasabah';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: Column(
        children: [
          // Dark Navy Header (matching PDF Page 1)
          Container(
            color: const Color(0xFF102A43),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                child: Row(
                  children: [
                    Material(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Halo, $displayName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 13.5, color: Colors.white.withOpacity(0.75)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  meetingFull,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _fetchLoanData,
                        child: const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(Icons.refresh_rounded, size: 19, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchLoanData,
              color: const Color(0xFF0A4B8F),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  // Blue Card: Harus dibayar minggu ini
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0C4D93), Color(0xFF083972)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0C4D93).withOpacity(0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
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
                              'Harus dibayar minggu ini',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.88),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: allSudahSetor
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                allSudahSetor ? 'Sudah dibayar' : 'Belum dibayar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: allSudahSetor
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormatter.formatRupiah(totalHarusDibayar),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._kkmLoans.map((b) {
                          final jenis = (b.kkm['jenis'] ?? b.detail['jenis_kkm'] ?? '').toString().toLowerCase();
                          final title = jenis == 'kilat' ? 'KILAT KKM' : 'KKM Reguler';
                          final mIni = b.kkm['minggu_ini'] is Map
                              ? Map<String, dynamic>.from(b.kkm['minggu_ini'] as Map)
                              : <String, dynamic>{};
                          final ke = mIni['minggu_ke']?.toString();
                          final setoranMinggu = Money.tryParse(mIni['setoran']) ?? Money.zero();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ke != null ? '$title (ke-$ke)' : title,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.formatRupiah(setoranMinggu),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (totalTunggakKali > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFACC15), size: 17),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Tunggakan $totalTunggakKali kali',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.formatRupiah(totalTunggakNominal),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nomor Virtual Account',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      color: Colors.white.withOpacity(0.75),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    vaNumber ?? 'Belum tersedia',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (vaNumber != null)
                              Material(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: vaNumber!));
                                    _showToast('Nomor VA disalin: $vaNumber');
                                  },
                                  child: const SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: Icon(Icons.copy_rounded, color: Colors.white, size: 19),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Individual KKM Loan Progress Cards
                  ...List.generate(_kkmLoans.length, (idx) {
                    final b = _kkmLoans[idx];
                    final jenis = (b.kkm['jenis'] ?? b.detail['jenis_kkm'] ?? '').toString().toLowerCase();
                    final title = jenis == 'kilat' ? 'KILAT KKM' : 'KKM Reguler';
                    final plafon = Money.tryParse(b.detail['plafon'] ?? b.account['plafon']) ?? Money.zero();
                    final setoran = b.kkm['setoran'] is Map
                        ? Map<String, dynamic>.from(b.kkm['setoran'] as Map)
                        : <String, dynamic>{};
                    final tunggakan = setoran['tunggakan'] is Map
                        ? Map<String, dynamic>.from(setoran['tunggakan'] as Map)
                        : <String, dynamic>{};
                    final jumlah = int.tryParse((setoran['jumlah'] ?? '0').toString()) ?? 0;
                    final sudah = int.tryParse((setoran['sudah'] ?? '0').toString()) ?? 0;
                    final sisa = int.tryParse((setoran['sisa'] ?? '0').toString()) ?? 0;
                    final tunggakKali = int.tryParse((tunggakan['kali'] ?? '0').toString()) ?? 0;
                    final progress = jumlah > 0 ? (sudah / jumlah).clamp(0.0, 1.0) : 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderLight),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LoanKkmDetailScreen(
                                  kkmLoans: _kkmLoans,
                                  initialLoanIndex: idx,
                                  initialTabIndex: 0,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$title • ${CurrencyFormatter.formatRupiah(plafon)}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: titleDark,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, color: textMuted),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Sisa $sisa dari $jumlah kali bayar',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: textMuted,
                                        ),
                                      ),
                                    ),
                                    if (tunggakKali > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          'Tunggak $tunggakKali kali',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFFB91C1C),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 6,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  // Quick Buttons: Info Pinjaman & Bayar & Hadir
                  Row(
                    children: [
                      Expanded(
                        child: _buildKkmQuickButton(
                          icon: Icons.description_outlined,
                          iconBg: const Color(0xFFEBF3FF),
                          iconColor: const Color(0xFF0C4D93),
                          label: 'Info Pinjaman',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LoanKkmDetailScreen(
                                  kkmLoans: _kkmLoans,
                                  initialLoanIndex: 0,
                                  initialTabIndex: 0,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildKkmQuickButton(
                          icon: Icons.check_circle_outline_rounded,
                          iconBg: const Color(0xFFEAF7EE),
                          iconColor: const Color(0xFF15803D),
                          label: 'Bayar & Hadir',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LoanKkmDetailScreen(
                                  kkmLoans: _kkmLoans,
                                  initialLoanIndex: 0,
                                  initialTabIndex: 1,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  if (_regularLoans.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Fasilitas Kredit Lainnya',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: titleDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._regularLoans.map((loan) {
                      final accNo = (loan['nomor_rekening'] ?? '-').toString();
                      final prodName = (loan['nama_produk'] ?? 'Kredit').toString();
                      final baki = Money.tryParse(loan['baki_debet']) ?? Money.zero();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderLight),
                        ),
                        child: ListTile(
                          title: Text(
                            prodName,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w800, color: titleDark),
                          ),
                          subtitle: Text(
                            'No. Rek: $accNo • Sisa: ${CurrencyFormatter.formatRupiah(baki)}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded, color: textMuted),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LoanDetailScreen(
                                  initialLoan: loan,
                                  initialDetail: _detailsByAcc[accNo],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKkmQuickButton({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderLight),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: titleDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatShortDate(dynamic raw) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return '-';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} $yy';
  }
}
