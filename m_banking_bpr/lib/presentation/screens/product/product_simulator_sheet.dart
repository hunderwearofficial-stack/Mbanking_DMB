import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';
import '../../../core/constants/product_rates.dart';
import '../../../core/money/money.dart';
import '../../widgets/app_validation_feedback.dart';

class ProductSimulatorSheet extends StatefulWidget {
  final String initialType; // 'DEPOSITO' or 'PINJAMAN'

  const ProductSimulatorSheet({super.key, this.initialType = 'DEPOSITO'});

  static void show(BuildContext context, {String initialType = 'DEPOSITO'}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductSimulatorSheet(initialType: initialType),
    );
  }

  @override
  State<ProductSimulatorSheet> createState() => _ProductSimulatorSheetState();
}

class _ProductSimulatorSheetState extends State<ProductSimulatorSheet> {
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);

  late String _selectedType;
  // Nominal in whole rupiah (integer). The slider uses a double only for its UI position.
  int _amountRupiah = 25000000;
  Money get _amount => Money.rupiah(_amountRupiah);
  int _tenorMonths = 6;
  final TextEditingController _purposeController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _tenorMonths = _selectedType == 'DEPOSITO' ? 6 : 12;
  }

  @override
  void dispose() {
    _purposeController.dispose();
    super.dispose();
  }

  // Illustrative rates only (see ProductRates); results are estimates, not offers.
  int get _annualRateBps => _selectedType == 'DEPOSITO' ? ProductRates.depositoAnnualBps : ProductRates.kreditAnnualBps;

  /// Integer division rounded half up (amounts are non-negative).
  static int _divRound(int numerator, int denominator) => (numerator + denominator ~/ 2) ~/ denominator;

  /// Estimate in exact integer sen: deposit = net interest for the tenor (after 20% tax);
  /// loan = monthly installment (principal + flat interest).
  Money get _estimatedCalculation {
    final sen = _amount.sen;
    if (_selectedType == 'DEPOSITO') {
      final gross = _divRound(sen * _annualRateBps * _tenorMonths, 12 * 10000);
      return Money.sen(_divRound(gross * 80, 100));
    }
    final principalPerMonth = _divRound(sen, _tenorMonths);
    final interestPerMonth = _divRound(sen * _annualRateBps, 12 * 10000);
    return Money.sen(principalPerMonth + interestPerMonth);
  }

  Future<void> _submitApplication() async {
    setState(() => _submitting = true);
    try {
      final accountRepo = context.read<AccountCubit>().accountRepository;
      final isDeposito = _selectedType == 'DEPOSITO';
      await accountRepo.submitProductApplication(
        productType: _selectedType,
        productName: isDeposito ? 'Deposito Berjangka DMB' : 'Kredit Modal Kerja / Multiguna DMB',
        amount: _amount,
        tenorMonths: _tenorMonths,
        interestRate: isDeposito ? ProductRates.depositoLabel : ProductRates.kreditLabel,
        estimatedReturn: _estimatedCalculation,
        purposeOrSource: _purposeController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.showSuccess(
        context,
        isDeposito
            ? 'Pengajuan Deposito Berjangka berhasil dikirim! Petugas Bank DMB akan segera memproses.'
            : 'Pengajuan Fasilitas Pinjaman berhasil dikirim! Tim Kredit Bank DMB akan segera menghubungi Anda.',
        title: 'Pengajuan Terkirim',
      );
    } on ApiException catch (e) {
      setState(() => _submitting = false);
      if (!mounted) return;
      AppToast.showError(context, e.message, title: 'Validasi Pengajuan');
    } catch (e) {
      setState(() => _submitting = false);
      if (!mounted) return;
      AppToast.showError(context, 'Gagal mengirim pengajuan: $e', title: 'Gagal Memproses');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDeposito = _selectedType == 'DEPOSITO';
    final tenors = isDeposito ? [1, 3, 6, 12] : [6, 12, 24, 36];
    if (!tenors.contains(_tenorMonths)) {
      _tenorMonths = tenors.first;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
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

              // Segmented Switcher (Deposito vs Pinjaman)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedType = 'DEPOSITO';
                          _tenorMonths = 6;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: isDeposito
                                ? const LinearGradient(
                                    colors: [primaryNavy, royalBlue],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: isDeposito ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: isDeposito
                                ? [
                                    BoxShadow(
                                      color: royalBlue.withOpacity(0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              'Deposito Berjangka',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isDeposito ? Colors.white : textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedType = 'PINJAMAN';
                          _tenorMonths = 12;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: !isDeposito
                                ? const LinearGradient(
                                    colors: [primaryNavy, royalBlue],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: !isDeposito ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: !isDeposito
                                ? [
                                    BoxShadow(
                                      color: royalBlue.withOpacity(0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              'Simulasi Pinjaman',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: !isDeposito ? Colors.white : textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Nominal Slider (with Expanded to prevent overflow)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      isDeposito ? 'Nominal Penempatan Deposito' : 'Plafon Pinjaman Diajukan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.formatRupiah(_amount),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                      color: royalBlue,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: royalBlue,
                  inactiveTrackColor: const Color(0xFFE2E8F0),
                  thumbColor: royalBlue,
                  overlayColor: royalBlue.withOpacity(0.15),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _amountRupiah.toDouble(),
                  min: 5000000,
                  max: 250000000,
                  divisions: 49,
                  // Slider positions are multiples of Rp 5.000.000; store as integer rupiah.
                  onChanged: (val) => setState(() => _amountRupiah = (val / 5000000).round() * 5000000),
                ),
              ),
              const SizedBox(height: 8),

              // Tenor Selection Chips
              Text(
                'Pilih Jangka Waktu (Tenor)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: tenors.map((t) {
                  final active = _tenorMonths == t;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Center(
                          child: Text(
                            '$t Bln',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                              color: active ? royalBlue : titleDark,
                            ),
                          ),
                        ),
                        selected: active,
                        selectedColor: const Color(0xFFEFF6FF),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: active ? royalBlue : borderLight,
                          width: active ? 1.5 : 1,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (_) => setState(() => _tenorMonths = t),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Live Calculation Result Card (Royal Navy Blue Gradient - Unified Theme)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0B356D),
                      Color(0xFF0062E3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: royalBlue.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            isDeposito ? 'Estimasi Bunga Bersih (Net)' : 'Estimasi Angsuran / Bulan',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isDeposito ? ProductRates.depositoLabel : ProductRates.kreditLabel,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      CurrencyFormatter.formatRupiah(_estimatedCalculation),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isDeposito
                          ? 'Total Dana + Bunga saat jatuh tempo ($_tenorMonths bln): ${CurrencyFormatter.formatRupiah(_amount + _estimatedCalculation)}'
                          : 'Plafon ${CurrencyFormatter.formatRupiah(_amount)} selama $_tenorMonths bulan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _purposeController,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: titleDark),
                decoration: InputDecoration(
                  labelText: isDeposito ? 'Sumber Dana / Catatan (Opsional)' : 'Tujuan Penggunaan Pinjaman / Agunan',
                  labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted),
                  hintText: isDeposito ? 'Contoh: Debet Rekening Tabungan DMB' : 'Contoh: Tambahan Modal Usaha Toko',
                  hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted.withOpacity(0.6)),
                  prefixIcon: const Icon(Icons.edit_note_rounded, color: royalBlue),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: royalBlue, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _submitting ? null : _submitApplication,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 17),
                  label: Text(
                    isDeposito ? 'Ajukan Pembukaan Deposito Sekarang' : 'Ajukan Fasilitas Pinjaman Sekarang',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
