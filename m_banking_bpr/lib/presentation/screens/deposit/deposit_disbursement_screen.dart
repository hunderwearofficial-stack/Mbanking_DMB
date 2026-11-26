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

class DepositDisbursementScreen extends StatefulWidget {
  final Map<String, dynamic> depositDetail;

  const DepositDisbursementScreen({
    super.key,
    required this.depositDetail,
  });

  @override
  State<DepositDisbursementScreen> createState() =>
      _DepositDisbursementScreenState();
}

class _DepositDisbursementScreenState extends State<DepositDisbursementScreen> {
  static const Color deepCobalt = AuthUiTokens.deepCobalt;
  static const Color titleDark = AuthUiTokens.titleDark;
  static const Color textMuted = AuthUiTokens.textMuted;

  static const List<String> _disbursementTypes = [
    'Pokok',
    'Bunga',
    'Pokok & Bunga',
  ];

  static const List<String> _bankOptions = [
    'Bank DMB (Tabungan DMB)',
    'BCA',
    'BRI',
    'BNI',
    'Mandiri',
    'BSI',
    'CIMB Niaga',
    'Danamon',
    'Permata',
    'Bank Lainnya',
  ];

  String? _selectedType;
  String? _selectedBank;
  final TextEditingController _accountController = TextEditingController();
  bool _agreed = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _accountController.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    if (_selectedType == null) {
      AppToast.showError(context, 'Silakan pilih jenis pencairan terlebih dahulu.');
      return;
    }
    if (_selectedBank == null) {
      AppToast.showError(context, 'Silakan pilih bank tujuan terlebih dahulu.');
      return;
    }
    final targetAcc = _accountController.text.trim();
    if (targetAcc.length < 5) {
      AppToast.showError(context, 'Nomor rekening tujuan tidak valid.');
      return;
    }
    if (!_agreed) {
      AppToast.showError(
        context,
        'Anda harus menyetujui Syarat & Ketentuan Bank DMB terlebih dahulu.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final d = widget.depositDetail;
      final accNo = (d['nomor_rekening'] ?? d['no_rekening'] ?? '').toString().trim();
      final bilyet = (d['nomor_bilyet'] ?? '-').toString().trim();
      final productName =
          (d['nama_produk'] ?? 'Deposito Berjangka').toString().trim();
      final tenor = int.tryParse((d['jangka_waktu_bulan'] ?? '1').toString()) ?? 1;
      final safeTenor = tenor > 0 ? tenor : 1;
      final nominal = Money.tryParse(d['nominal']) ?? Money.zero();
      final accrued = Money.tryParse(d['bunga_berjalan']) ?? Money.zero();
      final rateNum = double.tryParse((d['suku_bunga_tahunan'] ?? '0').toString()) ?? 0;
      final rateStr = rateNum > 0
          ? '${rateNum.toStringAsFixed(rateNum.truncateToDouble() == rateNum ? 0 : 2)}% p.a.'
          : '-';
      final estimatedMaturity = nominal + accrued;

      final labelProduct = bilyet.isNotEmpty && bilyet != '-'
          ? '$productName ($accNo • Bilyet $bilyet)'
          : '$productName ($accNo)';
      final purpose =
          'Jenis: $_selectedType | Bank: $_selectedBank | Rek: $targetAcc | Jatuh Tempo: ${_formatDate(d['tanggal_jatuh_tempo'])}';

      await context.read<AccountRepository>().submitProductApplication(
            productType: 'PENCAIRAN_DEPOSITO',
            productName: labelProduct,
            amount: nominal,
            tenorMonths: safeTenor,
            interestRate: rateStr,
            estimatedReturn: estimatedMaturity,
            purposeOrSource: purpose,
          );

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppToast.showSuccess(
        context,
        'Pengajuan pencairan deposito berhasil dikirim ke Bank DMB.',
        title: 'Pengajuan Terkirim',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppToast.showError(
        context,
        ApiException.humanize(
          e,
          fallback: 'Gagal mengirim pengajuan pencairan. Silakan coba kembali.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.depositDetail;
    final productName =
        (d['nama_produk'] ?? 'Deposito Berjangka').toString().trim();
    final tenor = int.tryParse((d['jangka_waktu_bulan'] ?? '0').toString()) ?? 0;
    final nominal = Money.tryParse(d['nominal']) ?? Money.zero();
    final accrued = Money.tryParse(d['bunga_berjalan']) ?? Money.zero();
    final totalMaturity = nominal + accrued;
    final rateNum = double.tryParse((d['suku_bunga_tahunan'] ?? '0').toString()) ?? 0;
    final rateStr = rateNum > 0
        ? '${rateNum.toStringAsFixed(rateNum.truncateToDouble() == rateNum ? 0 : 2)}% p.a.'
        : '-';
    final subtitleText =
        tenor > 0 ? '$productName • $tenor Bulan' : productName;

    return AuthSwooshCanvas(
      child: SafeArea(
        child: Column(
          children: [
            // Header
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
                          'Pengajuan Pencairan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Blue Summary Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF033172), Color(0xFF0550A6)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: deepCobalt.withOpacity(0.22),
                            blurRadius: 16,
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
                              Expanded(
                                child: Text(
                                  subtitleText,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F7F1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'AKTIF',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F9D76),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Penempatan deposito',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.82),
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Maturity Info Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5ECF5)),
                      ),
                      child: Column(
                        children: [
                          _infoRow('Jatuh tempo',
                              _formatDate(d['tanggal_jatuh_tempo'])),
                          const SizedBox(height: 12),
                          _infoRow(
                            'Bunga deposito',
                            rateStr,
                            valueColor: const Color(0xFF0F9D76),
                          ),
                          const SizedBox(height: 12),
                          _infoRow(
                            'Total pendapatan saat ini',
                            CurrencyFormatter.formatRupiah(totalMaturity),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Form Data Pencairan
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5ECF5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Data Pencairan',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _fieldLabel('Jenis pencairan'),
                          const SizedBox(height: 8),
                          _buildDropdown(
                            value: _selectedType,
                            hint: 'Pilih jenis pencairan',
                            items: _disbursementTypes,
                            onChanged: (v) => setState(() => _selectedType = v),
                          ),
                          const SizedBox(height: 16),
                          _fieldLabel('Pilih bank'),
                          const SizedBox(height: 8),
                          _buildDropdown(
                            value: _selectedBank,
                            hint: 'Pilih bank tujuan',
                            items: _bankOptions,
                            onChanged: (v) => setState(() => _selectedBank = v),
                          ),
                          const SizedBox(height: 16),
                          _fieldLabel('Nomor rekening tujuan'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _accountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: titleDark,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ketik nomor rekening',
                              hintStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF3F6FA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Yellow Warning Notice
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF6E4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFDE6B0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFB45309),
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Pencairan sebelum jatuh tempo mengikuti ketentuan Bank DMB (dapat dikenakan biaya penalti dan penyesuaian bunga berjalan sesuai ketentuan berlaku).',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF78350F),
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Consent Checkbox
                    InkWell(
                      onTap: () => setState(() => _agreed = !_agreed),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _agreed,
                                onChanged: (v) =>
                                    setState(() => _agreed = v ?? false),
                                activeColor: deepCobalt,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Saya menyetujui Syarat & Ketentuan Bank DMB dan menyatakan data di atas benar.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: titleDark,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: deepCobalt,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Kirim Pengajuan Pencairan',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: titleDark,
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: textMuted,
            ),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: titleDark),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: titleDark,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
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
        Text(
          value,
          textAlign: TextAlign.end,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: valueColor ?? titleDark,
          ),
        ),
      ],
    );
  }
}
