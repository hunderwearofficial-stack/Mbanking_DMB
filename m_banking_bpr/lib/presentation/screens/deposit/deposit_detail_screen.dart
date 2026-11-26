import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import 'deposit_disbursement_screen.dart';

class DepositDetailScreen extends StatefulWidget {
  final Map<String, dynamic> initialItem;

  const DepositDetailScreen({super.key, required this.initialItem});

  @override
  State<DepositDetailScreen> createState() => _DepositDetailScreenState();
}

class _DepositDetailScreenState extends State<DepositDetailScreen> {
  static const Color deepCobalt = AuthUiTokens.deepCobalt;
  static const Color royalBlue = AuthUiTokens.royalBlue;
  static const Color titleDark = AuthUiTokens.titleDark;
  static const Color textMuted = AuthUiTokens.textMuted;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _detail = {};

  String get _accountNumber =>
      (widget.initialItem['nomor_rekening'] ??
              widget.initialItem['no_rekening'] ??
              '')
          .toString()
          .trim();

  @override
  void initState() {
    super.initState();
    _detail = Map<String, dynamic>.from(widget.initialItem);
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    if (_accountNumber.isEmpty || _accountNumber == '-') {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repo = context.read<AccountRepository>();
      final res = await repo.getDepositDetail(_accountNumber);
      if (!mounted) return;
      setState(() {
        if (res != null && res.isNotEmpty) {
          _detail = {...widget.initialItem, ...res};
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ApiException.humanize(
          e,
          fallback: 'Detail deposito belum dapat dimuat dari server.',
        );
        _isLoading = false;
      });
    }
  }

  String _formatDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s == 'null' || s == '-') return '-';
    final dateOnly = s.contains('T') ? s.split('T').first : s;
    final parts = dateOnly.split('-');
    if (parts.length == 3) {
      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      final m = int.tryParse(parts[1]) ?? 0;
      if (m >= 1 && m <= 12) {
        return '${parts[2]} ${months[m]} ${parts[0]}';
      }
    }
    return dateOnly;
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final productName =
        (d['nama_produk'] ?? 'Deposito Berjangka').toString().trim();
    final accNo = (d['nomor_rekening'] ?? _accountNumber).toString().trim();
    final bilyet = (d['nomor_bilyet'] ?? '-').toString().trim();
    final tenor = int.tryParse((d['jangka_waktu_bulan'] ?? '0').toString()) ?? 0;
    final nominal = Money.tryParse(d['nominal']) ?? Money.zero();
    final accrued = Money.tryParse(d['bunga_berjalan']) ?? Money.zero();
    final blocked = Money.tryParse(d['saldo_blokir']) ??
        Money.tryParse(d['saldo_tertahan']) ??
        Money.zero();
    final rateNum = double.tryParse((d['suku_bunga_tahunan'] ?? '0').toString()) ?? 0;
    final rateStr = rateNum > 0
        ? '${rateNum.toStringAsFixed(rateNum.truncateToDouble() == rateNum ? 0 : 2)}% p.a.'
        : '-';
    final statusCode = int.tryParse((d['status_rekening'] ?? '1').toString()) ?? 1;
    final statusText = (d['status_rekening_keterangan'] ?? '').toString().trim();
    final isActive = statusCode == 1 ||
        statusText.toLowerCase() == 'aktif' ||
        (statusText.isEmpty && statusCode != 4 && statusCode != 2);
    final statusLabel = statusText.isNotEmpty
        ? statusText.toUpperCase()
        : (isActive ? 'AKTIF' : 'NON-AKTIF');

    final aro = d['aro'] == true || d['aro'].toString().toLowerCase() == 'true';
    final jenisAro = (d['jenis_aro'] ?? '').toString().trim();
    final aroLabel = aro
        ? (jenisAro.isNotEmpty ? 'Ya ($jenisAro)' : 'Ya (Otomatis)')
        : 'Tidak';
    final rekBunga = (d['rekening_pencairan_bunga'] ?? '').toString().trim();
    final namaKantor = (d['nama_kantor'] ?? '').toString().trim();

    return AuthSwooshCanvas(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
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
                          color: deepCobalt,
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
                          'Detail Deposito',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          bilyet != '-' && bilyet.isNotEmpty
                              ? 'Bilyet $bilyet'
                              : accNo,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
                        child: const Icon(
                          Icons.refresh_rounded,
                          size: 19,
                          color: deepCobalt,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: deepCobalt),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchDetail,
                      color: deepCobalt,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_errorMessage != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.warningLight,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.warningBorder),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: titleDark,
                                  ),
                                ),
                              ),

                            // Primary Navy Card
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF033172), Color(0xFF0550A6)],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: deepCobalt.withOpacity(0.24),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          productName,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? const Color(0xFFE6F7F1)
                                              : const Color(0xFFFEF3C7),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: isActive
                                                ? const Color(0xFF0F9D76)
                                                : const Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nominal Penempatan',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CurrencyFormatter.formatRupiah(nominal),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: accNo));
                                      AppToast.showSuccess(
                                          context, 'No. rekening disalin: $accNo');
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.credit_card_rounded,
                                            color: Color(0xFF00E5FF), size: 15),
                                        const SizedBox(width: 6),
                                        Text(
                                          accNo,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withOpacity(0.9),
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(Icons.copy_rounded,
                                            size: 13,
                                            color: Colors.white.withOpacity(0.7)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Bunga & Saldo Blokir Card
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border:
                                    Border.all(color: const Color(0xFFE5ECF5)),
                              ),
                              child: Column(
                                children: [
                                  _detailRow(
                                    'Suku Bunga',
                                    rateStr,
                                    valueColor: const Color(0xFF0F9D76),
                                  ),
                                  const Divider(
                                      height: 18, color: Color(0xFFF1F5F9)),
                                  _detailRow(
                                    'Bunga Berjalan',
                                    CurrencyFormatter.formatRupiah(accrued),
                                    valueColor: deepCobalt,
                                  ),
                                  const Divider(
                                      height: 18, color: Color(0xFFF1F5F9)),
                                  _detailRow(
                                    'Saldo Blokir',
                                    CurrencyFormatter.formatRupiah(blocked),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Informasi Bilyet & Jatuh Tempo
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border:
                                    Border.all(color: const Color(0xFFE5ECF5)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Informasi Bilyet & Jatuh Tempo',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: titleDark,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _detailRow(
                                      'Nomor Bilyet',
                                      bilyet.isNotEmpty ? bilyet : '-'),
                                  const Divider(
                                      height: 18, color: Color(0xFFF1F5F9)),
                                  _detailRow(
                                      'Jangka Waktu',
                                      tenor > 0 ? '$tenor Bulan' : '-'),
                                  const Divider(
                                      height: 18, color: Color(0xFFF1F5F9)),
                                  _detailRow('Tanggal Buka',
                                      _formatDate(d['tanggal_buka'])),
                                  const Divider(
                                      height: 18, color: Color(0xFFF1F5F9)),
                                  _detailRow('Tanggal Efektif',
                                      _formatDate(d['tanggal_efektif'])),
                                  const Divider(
                                      height: 18, color: Color(0xFFF1F5F9)),
                                  _detailRow('Tanggal Jatuh Tempo',
                                      _formatDate(d['tanggal_jatuh_tempo'])),
                                  const Divider(
                                      height: 18, color: Color(0xFFF1F5F9)),
                                  _detailRow('Perpanjangan Otomatis (ARO)',
                                      aroLabel),
                                  if (rekBunga.isNotEmpty) ...[
                                    const Divider(
                                        height: 18, color: Color(0xFFF1F5F9)),
                                    _detailRow('Rekening Pencairan Bunga',
                                        rekBunga),
                                  ],
                                  if (namaKantor.isNotEmpty) ...[
                                    const Divider(
                                        height: 18, color: Color(0xFFF1F5F9)),
                                    _detailRow('Kantor Pembukaan', namaKantor),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 22),

                            if (isActive)
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            DepositDisbursementScreen(
                                          depositDetail: _detail,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                      Icons.payments_outlined,
                                      size: 20),
                                  label: Text(
                                    'Ajukan Pencairan Deposito',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: deepCobalt,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(26),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? titleDark,
            ),
          ),
        ),
      ],
    );
  }
}
