import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/empty_state_view.dart';

class LoanScheduleListScreen extends StatefulWidget {
  const LoanScheduleListScreen({super.key});

  @override
  State<LoanScheduleListScreen> createState() => _LoanScheduleListScreenState();
}

class _LoanScheduleListScreenState extends State<LoanScheduleListScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = Color(0xFFE2E8F0);

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _loans = [];
  final Map<String, Map<String, dynamic>> _details = {};

  @override
  void initState() {
    super.initState();
    _fetchLoans();
  }

  Future<void> _fetchLoans() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final authState = context.read<AuthCubit>().state;
      String? cif;
      if (authState is AuthAuthenticated) cif = authState.user.cif;
      if (cif == null || cif.isEmpty) {
        cif = await context.read<AuthCubit>().authRepository.secureStorage.getCIF();
      }
      if (!mounted) return;
      if (cif == null || cif.isEmpty) {
        setState(() {
          _loans = [];
          _isLoading = false;
        });
        return;
      }
      final repo = context.read<AccountRepository>();
      final loans = await repo.getLoans(cifNumber: cif);
      final Map<String, Map<String, dynamic>> detMap = {};
      await Future.wait(loans.map((l) async {
        final acc = (l['nomor_rekening'] ?? '').toString().trim();
        if (acc.isNotEmpty) {
          try {
            final d = await repo.getLoanDetail(acc, cifNumber: cif);
            if (d != null) detMap[acc] = d;
          } catch (_) {}
        }
      }));
      if (mounted) {
        setState(() {
          _loans = loans;
          _details
            ..clear()
            ..addAll(detMap);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiException.humanize(e, fallback: 'Gagal memuat daftar pinjaman.');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Jadwal Angsuran',
          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _fetchLoans,
            icon: const Icon(Icons.refresh_rounded, color: primaryNavy, size: 21),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLoans,
        color: primaryNavy,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryNavy))
            : _errorMessage != null
                ? Center(child: Text(_errorMessage!, textAlign: TextAlign.center))
                : _loans.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 36),
                          EmptyStateView(
                            icon: Icons.calendar_today_outlined,
                            title: 'Belum Ada Pinjaman Aktif',
                            subtitle: 'Jadwal angsuran akan tampil otomatis jika Anda memiliki fasilitas pinjaman aktif.',
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 2, bottom: 8),
                            child: Text(
                              'PILIH REKENING PINJAMAN',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: textMuted,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderLight),
                            ),
                            child: Column(
                              children: List.generate(_loans.length, (i) {
                                final loan = _loans[i];
                                final accNo = (loan['nomor_rekening'] ?? '-').toString();
                                final detail = _details[accNo] ?? loan;
                                final prodName = (detail['nama_produk'] ?? 'Fasilitas Pinjaman').toString();
                                final baki = Money.tryParse(detail['baki_debet']) ?? Money.zero();
                                final jadwal = detail['jadwal'] is List ? (detail['jadwal'] as List) : [];
                                final progres = detail['progres'] is Map
                                    ? Map<String, dynamic>.from(detail['progres'] as Map)
                                    : <String, dynamic>{};
                                final sisaBayar = progres['sisa_bayar']?.toString() ?? '-';

                                return Column(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => LoanScheduleDetailScreen(
                                              loan: loan,
                                              detail: detail,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    prodName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w700,
                                                      color: titleDark,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '$accNo • Sisa $sisaBayar kali (${jadwal.length} jadwal)',
                                                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Sisa Pokok: ${CurrencyFormatter.formatRupiah(baki)}',
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: primaryNavy,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (i < _loans.length - 1)
                                      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}

class LoanScheduleDetailScreen extends StatelessWidget {
  final Map<String, dynamic> loan;
  final Map<String, dynamic> detail;

  const LoanScheduleDetailScreen({
    super.key,
    required this.loan,
    required this.detail,
  });

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    final prodName = (detail['nama_produk'] ?? loan['nama_produk'] ?? 'Pinjaman').toString();
    final accNo = (detail['nomor_rekening'] ?? loan['nomor_rekening'] ?? '-').toString();
    final jadwal = detail['jadwal'] is List
        ? (detail['jadwal'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jadwal Angsuran',
              style: GoogleFonts.plusJakartaSans(fontSize: 16.5, fontWeight: FontWeight.w700),
            ),
            Text(
              '$prodName • $accNo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: jadwal.isEmpty
          ? Center(
              child: Text(
                'Belum ada jadwal angsuran tersedia.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderLight),
                  ),
                  child: Column(
                    children: List.generate(jadwal.length, (i) {
                      final row = jadwal[i];
                      final ke = row['ke']?.toString() ?? '${i + 1}';
                      final tgl = _formatDate(row['tanggal']);
                      final tagihan = Money.tryParse(row['tagihan']) ?? Money.zero();
                      final dibayar = Money.tryParse(row['dibayar']) ?? Money.zero();
                      final status = (row['status'] ?? '').toString().toLowerCase();

                      Color bg = const Color(0xFFF1F5F9);
                      Color fg = titleDark;
                      String label = 'Akan Datang';
                      if (status == 'lunas') {
                        bg = const Color(0xFFDCFCE7);
                        fg = const Color(0xFF15803D);
                        label = 'Lunas';
                      } else if (status == 'tunggak') {
                        bg = const Color(0xFFFEE2E2);
                        fg = const Color(0xFFB91C1C);
                        label = 'Tunggak';
                      }

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '#$ke',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: primaryNavy,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tgl,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: titleDark,
                                        ),
                                      ),
                                      Text(
                                        'Tagihan ${CurrencyFormatter.formatRupiah(tagihan)} • Bayar ${CurrencyFormatter.formatRupiah(dibayar)}',
                                        style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                                  child: Text(
                                    label,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: fg,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < jadwal.length - 1)
                            const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw.toString().trim());
    if (dt == null) return raw.toString();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
