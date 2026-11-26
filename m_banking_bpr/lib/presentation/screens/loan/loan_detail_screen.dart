import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';

class LoanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> initialLoan;
  final Map<String, dynamic>? initialDetail;

  const LoanDetailScreen({
    super.key,
    required this.initialLoan,
    this.initialDetail,
  });

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;

  bool _isLoading = true;
  late Map<String, dynamic> _detail;

  @override
  void initState() {
    super.initState();
    _detail = {
      ...widget.initialLoan,
      if (widget.initialDetail != null) ...widget.initialDetail!,
    };
    if (widget.initialDetail != null) {
      _isLoading = false;
    } else {
      _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthCubit>().state;
      String? cif;
      if (authState is AuthAuthenticated) cif = authState.user.cif;
      if (cif == null || cif.isEmpty) {
        cif = await context.read<AuthCubit>().authRepository.secureStorage.getCIF();
      }
      final accNo = (widget.initialLoan['nomor_rekening'] ?? '').toString();
      if (!mounted || accNo.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      final res = await context.read<AccountRepository>().getLoanDetail(accNo, cifNumber: cif);
      if (mounted) {
        setState(() {
          if (res != null) _detail = {..._detail, ...res};
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prodName = (_detail['nama_produk'] ?? 'Fasilitas Kredit').toString();
    final accNo = (_detail['nomor_rekening'] ?? '-').toString();
    final bakiDebet = Money.tryParse(_detail['baki_debet']) ?? Money.zero();
    final plafon = Money.tryParse(_detail['plafon']) ?? Money.zero();
    final angsuran = Money.tryParse(_detail['angsuran']);
    final kol = (_detail['kolektibilitas_keterangan'] ?? 'Lancar').toString();
    final statusKet = (_detail['status_rekening_keterangan'] ?? 'Aktif').toString();
    final va = _detail['virtual_account']?.toString().trim();

    final progres = _detail['progres'] is Map
        ? Map<String, dynamic>.from(_detail['progres'] as Map)
        : <String, dynamic>{};
    final tunggakan = progres['tunggakan'] is Map
        ? Map<String, dynamic>.from(progres['tunggakan'] as Map)
        : <String, dynamic>{};
    final totalAngsuran = int.tryParse((progres['jumlah_angsuran'] ?? _detail['jangka_waktu'] ?? '0').toString()) ?? 0;
    final sudahBayar = int.tryParse((progres['sudah_bayar'] ?? '0').toString()) ?? 0;
    final tunggakKali = int.tryParse((tunggakan['kali'] ?? '0').toString()) ?? 0;
    final tunggakNominal = Money.tryParse(tunggakan['nominal']) ?? Money.zero();
    final sisaBayar = int.tryParse((progres['sisa_bayar'] ?? '0').toString()) ?? 0;
    final sisaTagihan = Money.tryParse(progres['sisa_tagihan']) ?? bakiDebet;

    final jadwal = _detail['jadwal'] is List
        ? (_detail['jadwal'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    final agunan = _detail['agunan'] is List
        ? (_detail['agunan'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    final progressRatio = totalAngsuran > 0 ? (sudahBayar / totalAngsuran).clamp(0.0, 1.0) : 0.0;

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prodName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                          ),
                        ),
                        Text(
                          'No. Rekening: $accNo',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _fetchDetail,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AuthUiTokens.inputBorder),
                        ),
                        child: const Icon(Icons.refresh_rounded, size: 19, color: AuthUiTokens.deepCobalt),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_isLoading)
              const LinearProgressIndicator(minHeight: 2, color: primaryNavy, backgroundColor: borderLight),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchDetail,
                color: primaryNavy,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
                  children: [
                    // Blue Hero Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0A2E63), Color(0xFF033172)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Sisa Pokok Pinjaman',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$statusKet • $kol',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            CurrencyFormatter.formatRupiah(bakiDebet),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progressRatio,
                              minHeight: 7,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4ADE80)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Sudah bayar $sudahBayar dari $totalAngsuran kali',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                              Text(
                                'Sisa $sisaBayar kali',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (va != null && va.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Nomor Virtual Account',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10.5,
                                            color: Colors.white.withOpacity(0.75),
                                          ),
                                        ),
                                        Text(
                                          va,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: va));
                                      AppToast.showSuccess(context, 'Nomor VA berhasil disalin');
                                    },
                                    icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (tunggakKali > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFB91C1C), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Terdapat tunggakan $tunggakKali kali angsuran sebesar ${CurrencyFormatter.formatRupiah(tunggakNominal)}.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF991B1B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    // Info Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Informasi Fasilitas Kredit',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _infoRow('Plafon Awal', CurrencyFormatter.formatRupiah(plafon)),
                          _infoRow('Sisa Tagihan', CurrencyFormatter.formatRupiah(sisaTagihan)),
                          if (angsuran != null)
                            _infoRow('Angsuran Berikutnya', CurrencyFormatter.formatRupiah(angsuran)),
                          _infoRow('Jatuh Tempo Berikutnya', _formatDate(_detail['jatuh_tempo_berikutnya'])),
                          _infoRow('Jatuh Tempo Akhir', _formatDate(_detail['tanggal_jatuh_tempo'])),
                          _infoRow('Tenor', '${_detail['jangka_waktu'] ?? '-'} ${_detail['satuan_waktu'] ?? 'bulan'}'),
                          _infoRow('Suku Bunga', '${_detail['suku_bunga_tahunan'] ?? '-'}% p.a. (${_detail['metode_bunga'] ?? '-'})'),
                          _infoRow('No. Perjanjian', (_detail['nomor_perjanjian'] ?? '-').toString()),
                          _infoRow('Kantor Pelayanan', (_detail['nama_kantor'] ?? '-').toString()),
                        ],
                      ),
                    ),

                    if (agunan.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderLight),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Agunan / Jaminan',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...agunan.map((a) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.verified_user_outlined, size: 17, color: primaryNavy),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${a['jenis'] ?? '-'} (${a['bukti_kepemilikan'] ?? '-'})',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: titleDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    // Jadwal Angsuran
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Jadwal Angsuran (${jadwal.length})',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (jadwal.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Belum ada jadwal angsuran tersedia.',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted),
                              ),
                            )
                          else
                            ...jadwal.map((row) {
                              final ke = row['ke']?.toString() ?? '-';
                              final tgl = _formatDate(row['tanggal']);
                              final tagihan = Money.tryParse(row['tagihan']) ?? Money.zero();
                              final status = (row['status'] ?? '').toString().toLowerCase();

                              Color bg = const Color(0xFFE2E8F0);
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

                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 34,
                                      child: Text(
                                        '#$ke',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
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
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: titleDark,
                                            ),
                                          ),
                                          Text(
                                            CurrencyFormatter.formatRupiah(tagihan),
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        label,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: fg,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: titleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return '-';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
