import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/product_rates.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../widgets/auth_ui_kit.dart';

class DepositProductOption {
  final String name;
  final int tenorMonths;
  final double ratePercent;
  final String description;

  const DepositProductOption({
    required this.name,
    required this.tenorMonths,
    required this.ratePercent,
    required this.description,
  });
}

class DepositApplicationBottomSheet extends StatefulWidget {
  final VoidCallback? onSuccess;

  const DepositApplicationBottomSheet({super.key, this.onSuccess});

  static Future<void> show(BuildContext context, {VoidCallback? onSuccess}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DepositApplicationBottomSheet(onSuccess: onSuccess),
      ),
    );
  }

  @override
  State<DepositApplicationBottomSheet> createState() => _DepositApplicationBottomSheetState();
}

class _DepositApplicationBottomSheetState extends State<DepositApplicationBottomSheet> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  static const List<int> _quickAmounts = [
    5000000,
    10000000,
    25000000,
    50000000,
    100000000,
  ];

  static const List<String> _aroOptions = [
    'Perpanjangan Pokok Otomatis (ARO Pokok)',
    'Perpanjangan Pokok + Bunga (Roll-over)',
    'Tidak Diperpanjang (Cair ke Tabungan)',
  ];

  late List<DepositProductOption> _products;
  late DepositProductOption _selectedProduct;
  late String _selectedAro;
  final TextEditingController _amountController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'id_ID');

  int _nominal = 10000000;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<DepositProductOption> _buildDefaultOptions() {
    final maxRate = ProductRates.depositoAnnualBps / 100.0;
    return [
      DepositProductOption(
        name: 'Deposito Berjangka DMB 1 Bulan',
        tenorMonths: 1,
        ratePercent: (maxRate - 1.25).clamp(2.5, maxRate),
        description: 'Tenor singkat dengan fleksibilitas likuiditas tinggi.',
      ),
      DepositProductOption(
        name: 'Deposito Berjangka DMB 3 Bulan',
        tenorMonths: 3,
        ratePercent: (maxRate - 0.75).clamp(3.0, maxRate),
        description: 'Pilihan favorit untuk penempatan dana jangka menengah.',
      ),
      DepositProductOption(
        name: 'Deposito Berjangka DMB 6 Bulan',
        tenorMonths: 6,
        ratePercent: (maxRate - 0.25).clamp(3.5, maxRate),
        description: 'Imbal hasil optimal di atas suku bunga rata-rata pasar.',
      ),
      DepositProductOption(
        name: 'Deposito Berjangka DMB 12 Bulan',
        tenorMonths: 12,
        ratePercent: maxRate,
        description: 'Imbal hasil tertinggi dengan perlindungan penjaminan LPS.',
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _products = _buildDefaultOptions();
    _selectedProduct = _products.length > 1 ? _products[1] : _products.first;
    _selectedAro = _aroOptions[0];
    _amountController.text = _currencyFormat.format(_nominal);
    _fetchCatalogProducts();
  }

  Future<void> _fetchCatalogProducts() async {
    try {
      final repo = context.read<AccountRepository>();
      final cat = await repo.getProductsCatalog();
      final depList = cat?['deposito'];
      if (depList is List && depList.isNotEmpty && mounted) {
        final firstName = (depList.first is Map ? depList.first['nama_produk']?.toString() : null) ?? '';
        if (firstName.isNotEmpty) {
          final maxRate = ProductRates.depositoAnnualBps / 100.0;
          setState(() {
            _products = [
              DepositProductOption(
                name: '$firstName (1 Bulan)',
                tenorMonths: 1,
                ratePercent: (maxRate - 1.25).clamp(2.5, maxRate),
                description: 'Tenor singkat dengan fleksibilitas likuiditas tinggi.',
              ),
              DepositProductOption(
                name: '$firstName (3 Bulan)',
                tenorMonths: 3,
                ratePercent: (maxRate - 0.75).clamp(3.0, maxRate),
                description: 'Pilihan favorit untuk penempatan dana jangka menengah.',
              ),
              DepositProductOption(
                name: '$firstName (6 Bulan)',
                tenorMonths: 6,
                ratePercent: (maxRate - 0.25).clamp(3.5, maxRate),
                description: 'Imbal hasil optimal di atas suku bunga rata-rata pasar.',
              ),
              DepositProductOption(
                name: '$firstName (12 Bulan)',
                tenorMonths: 12,
                ratePercent: maxRate,
                description: 'Imbal hasil tertinggi dengan perlindungan penjaminan LPS.',
              ),
            ];
            _selectedProduct = _products.firstWhere(
              (p) => p.tenorMonths == _selectedProduct.tenorMonths,
              orElse: () => _products[1],
            );
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged(String val) {
    final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(clean) ?? 0;
    setState(() {
      _nominal = parsed;
      _errorMessage = null;
    });
  }

  void _selectQuickAmount(int amount) {
    setState(() {
      _nominal = amount;
      _amountController.text = _currencyFormat.format(amount);
      _errorMessage = null;
    });
  }

  int get _grossReturn {
    if (_nominal <= 0) return 0;
    final gross = (_nominal * (_selectedProduct.ratePercent / 100.0) * (_selectedProduct.tenorMonths / 12.0));
    return gross.round();
  }

  bool get _isTaxable => _nominal > ProductRates.depositoTaxThreshold;

  int get _taxDeduction {
    if (!_isTaxable) return 0;
    return (_grossReturn * (ProductRates.depositoTaxPercent / 100.0)).round();
  }

  int get _netReturn => _grossReturn - _taxDeduction;

  Future<void> _submitApplication() async {
    final minAmount = ProductRates.depositoMinAmount;
    final maxAmount = ProductRates.depositoMaxAmount;
    if (_nominal < minAmount) {
      setState(() {
        _errorMessage = 'Nominal penempatan minimal ${CurrencyFormatter.formatRupiah(Money.rupiah(minAmount))}';
      });
      return;
    }
    if (_nominal > maxAmount) {
      setState(() {
        _errorMessage = 'Nominal penempatan maksimal ${CurrencyFormatter.formatRupiah(Money.rupiah(maxAmount))}';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = context.read<AccountRepository>();
      await repo.submitProductApplication(
        productType: 'DEPOSITO',
        productName: _selectedProduct.name,
        amount: Money.rupiah(_nominal),
        tenorMonths: _selectedProduct.tenorMonths,
        interestRate: '${_selectedProduct.ratePercent.toStringAsFixed(2)}% p.a.',
        estimatedReturn: Money.rupiah(_netReturn),
        purposeOrSource: 'Instruksi: $_selectedAro',
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      _showSuccessDialog(context);
      widget.onSuccess?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiException.humanize(
            e,
            fallback: 'Pengajuan deposito belum dapat dikirim. Silakan coba kembali.',
          );
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSuccessDialog(BuildContext parentContext) {
    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: dmbGreen, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              'Pengajuan Terkirim!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pengajuan pembukaan ${_selectedProduct.name} dengan nominal ${CurrencyFormatter.formatRupiah(Money.rupiah(_nominal))} telah kami terima.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgCanvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: royalBlue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Petugas Account Officer Bank DMB akan menghubungi Anda untuk konfirmasi bilyet.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: titleDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Mengerti',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minAmountLabel = CurrencyFormatter.formatRupiah(Money.rupiah(ProductRates.depositoMinAmount));

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
                      'Buka Deposito',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AuthUiTokens.titleDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: AuthSurfaceCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Formulir Buka Deposito',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AuthUiTokens.titleDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Investasi resmi aman berizin OJK & dijamin LPS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Divider(height: 24, color: Color(0xFFF1F5F9)),

              Text(
                'Pilihan Tenor & Bunga',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              ..._products.map((p) {
                final isSelected = p.tenorMonths == _selectedProduct.tenorMonths;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedProduct = p;
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryLight : bgCanvas,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? royalBlue : borderLight,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: isSelected ? royalBlue : textMuted,
                          size: 19,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: titleDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.description,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFDCFCE7) : borderLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${p.ratePercent.toStringAsFixed(2)}% p.a.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? const Color(0xFF15803D) : titleDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),
              Text(
                'Nominal Penempatan (Min. $minAmountLabel)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: _onAmountChanged,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: primaryNavy,
                ),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  prefixStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: primaryNavy,
                  ),
                  filled: true,
                  fillColor: bgCanvas,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: royalBlue, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickAmounts.map((amt) {
                    final isCurrent = _nominal == amt;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          CurrencyFormatter.formatRupiah(Money.rupiah(amt)),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? Colors.white : titleDark,
                          ),
                        ),
                        backgroundColor: isCurrent ? primaryNavy : bgCanvas,
                        side: BorderSide(color: isCurrent ? primaryNavy : borderLight),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onPressed: () => _selectQuickAmount(amt),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 14),
              Text(
                'Instruksi Perpanjangan (ARO)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                value: _selectedAro,
                items: _aroOptions
                    .map((opt) => DropdownMenuItem(
                          value: opt,
                          child: Text(
                            opt,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedAro = val);
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgCanvas,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: borderLight),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.successBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimasi Bunga Kotor:',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted)),
                        Text(
                          CurrencyFormatter.formatRupiah(Money.rupiah(_grossReturn)),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: titleDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isTaxable
                              ? 'Pajak Deposito (${ProductRates.depositoTaxPercent}% > Rp 7,5 Jt):'
                              : 'Pajak Deposito (Bebas Pajak ≤ Rp 7,5 Jt):',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
                        ),
                        Text(
                          _isTaxable
                              ? '- ${CurrencyFormatter.formatRupiah(Money.rupiah(_taxDeduction))}'
                              : 'Rp 0',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _isTaxable ? AppColors.warning : dmbGreen,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: AppColors.successBorder),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimasi Bunga Bersih (Net):',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: dmbGreen)),
                        Text(
                          CurrencyFormatter.formatRupiah(Money.rupiah(_netReturn)),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: dmbGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimasi Total Jatuh Tempo:',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: titleDark)),
                        Text(
                          CurrencyFormatter.formatRupiah(Money.rupiah(_nominal + _netReturn)),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: primaryNavy,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.dangerBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: const Color(0xFF991B1B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

            ],
          ),
        ),
      ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: AuthGradientButton(
                  label: 'Kirim Pengajuan Deposito',
                  onPressed: _isSubmitting ? null : _submitApplication,
                  isLoading: _isSubmitting,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
