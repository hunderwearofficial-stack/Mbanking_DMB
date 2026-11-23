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

class LoanApplicationBottomSheet extends StatefulWidget {
  final VoidCallback? onSuccess;

  const LoanApplicationBottomSheet({super.key, this.onSuccess});

  static Future<void> show(BuildContext context, {VoidCallback? onSuccess}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoanApplicationBottomSheet(onSuccess: onSuccess),
      ),
    );
  }

  @override
  State<LoanApplicationBottomSheet> createState() => _LoanApplicationBottomSheetState();
}

class _LoanApplicationBottomSheetState extends State<LoanApplicationBottomSheet> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  static const List<String> _defaultLoanProducts = [
    'Kredit Modal Kerja DMB (Usaha/UMKM)',
    'Kredit Konsumtif / Multiguna',
    'Kredit Mikro & Investasi Usaha',
  ];

  static const List<int> _tenorOptions = [6, 12, 24, 36];

  static const List<int> _quickAmounts = [
    10000000,
    25000000,
    50000000,
    100000000,
  ];

  static const List<String> _purposes = [
    'Modal Usaha / Tambahan Modal Dagang',
    'Investasi Alat & Mesin Usaha',
    'Renovasi Rumah / Tempat Usaha',
    'Biaya Pendidikan & Keperluan Keluarga',
    'Kebutuhan Konsumtif & Multiguna',
  ];

  List<String> _loanProducts = List<String>.from(_defaultLoanProducts);
  late String _selectedProduct;
  late int _selectedTenor;
  late String _selectedPurpose;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _usageController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'id_ID');

  int _nominal = 25000000;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedProduct = _loanProducts[0];
    _selectedTenor = 12;
    _selectedPurpose = _purposes[0];
    _amountController.text = _currencyFormat.format(_nominal);
    _fetchCatalogProducts();
  }

  Future<void> _fetchCatalogProducts() async {
    try {
      final repo = context.read<AccountRepository>();
      final cat = await repo.getProductsCatalog();
      final kreditList = cat?['kredit'];
      if (kreditList is List && kreditList.isNotEmpty && mounted) {
        final names = kreditList
            .whereType<Map>()
            .map((m) => (m['nama_produk'] ?? '').toString().trim())
            .where((n) => n.isNotEmpty)
            .toList();
        if (names.isNotEmpty) {
          setState(() {
            _loanProducts = names;
            if (!_loanProducts.contains(_selectedProduct)) {
              _selectedProduct = _loanProducts.first;
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _amountController.dispose();
    _usageController.dispose();
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

  int get _estimatedMonthlyPrincipal {
    if (_nominal <= 0 || _selectedTenor <= 0) return 0;
    return (_nominal / _selectedTenor).round();
  }

  int get _estimatedMonthlyInterest {
    if (_nominal <= 0) return 0;
    final annualBps = ProductRates.kreditAnnualBps;
    return ((_nominal * annualBps) / (12 * 10000)).round();
  }

  int get _estimatedMonthlyInstallment => _estimatedMonthlyPrincipal + _estimatedMonthlyInterest;

  Future<void> _submitApplication() async {
    final minAmount = ProductRates.kreditMinAmount;
    final maxAmount = ProductRates.kreditMaxAmount;
    if (_nominal < minAmount) {
      setState(() {
        _errorMessage = 'Nominal pengajuan kredit minimal ${CurrencyFormatter.formatRupiah(Money.rupiah(minAmount))}';
      });
      return;
    }
    if (_nominal > maxAmount) {
      setState(() {
        _errorMessage = 'Nominal pengajuan kredit maksimal ${CurrencyFormatter.formatRupiah(Money.rupiah(maxAmount))}';
      });
      return;
    }

    final usageText = _usageController.text.trim();
    if (usageText.isEmpty) {
      setState(() {
        _errorMessage = 'Harap isi rincian penggunaan kredit';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = context.read<AccountRepository>();
      final purposeDetail = 'Tujuan: $_selectedPurpose | Rincian: $usageText';

      await repo.submitProductApplication(
        productType: 'PINJAMAN',
        productName: _selectedProduct,
        amount: Money.rupiah(_nominal),
        tenorMonths: _selectedTenor,
        interestRate: ProductRates.kreditLabel,
        estimatedReturn: Money.rupiah(_estimatedMonthlyInstallment),
        purposeOrSource: purposeDetail.length > 255 ? purposeDetail.substring(0, 255) : purposeDetail,
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
            fallback: 'Pengajuan kredit belum dapat dikirim. Silakan coba kembali.',
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
              'Pengajuan Kredit Diterima!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pengajuan pinjaman $_selectedProduct sebesar ${CurrencyFormatter.formatRupiah(Money.rupiah(_nominal))} (tenor $_selectedTenor bulan) berhasil dikirim.',
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
                  const Icon(Icons.support_agent_rounded, color: royalBlue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Account Officer Bank DMB akan menghubungi Anda untuk kelengkapan berkas dan survey usaha.',
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
                  'Selesai',
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
    final minAmountLabel = CurrencyFormatter.formatRupiah(Money.rupiah(ProductRates.kreditMinAmount));

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F6F2),
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF0A2A66),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 8,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 0.5,
            shadowColor: Colors.black.withOpacity(0.08),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: const Center(
                child: Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF0A2A66)),
              ),
            ),
          ),
        ),
        title: Text(
          'Ajukan Pinjaman',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0A2A66),
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Formulir Pengajuan Kredit',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0A2A66),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Solusi modal usaha & pinjaman terpercaya Bank DMB',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Divider(height: 24, color: Color(0xFFF1F5F9)),

              Text(
                'Jenis Produk Kredit',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                value: _selectedProduct,
                isExpanded: true,
                items: _loanProducts
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedProduct = val);
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

              const SizedBox(height: 14),
              Text(
                'Nominal Pinjaman yang Diajukan (Min. $minAmountLabel)',
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
                'Jangka Waktu Pinjaman (Tenor)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: _tenorOptions.map((t) {
                  final isSelected = _selectedTenor == t;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => setState(() => _selectedTenor = t),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryLight : bgCanvas,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? royalBlue : borderLight,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$t Bln',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? royalBlue : titleDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),
              Text(
                'Tujuan Pengajuan Kredit',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                value: _selectedPurpose,
                isExpanded: true,
                items: _purposes
                    .map((purp) => DropdownMenuItem(
                          value: purp,
                          child: Text(
                            purp,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPurpose = val);
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

              const SizedBox(height: 14),
              Text(
                'Rincian Penggunaan Dana Kredit',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _usageController,
                maxLines: 2,
                maxLength: 250,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: titleDark),
                decoration: InputDecoration(
                  hintText: 'Contoh: Tambahan stok barang sembako jelang hari raya...',
                  hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                  filled: true,
                  fillColor: bgCanvas,
                  contentPadding: const EdgeInsets.all(14),
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

              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Angsuran Pokok / Bulan:',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted)),
                        Text(
                          CurrencyFormatter.formatRupiah(Money.rupiah(_estimatedMonthlyPrincipal)),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: titleDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimasi Bunga (${ProductRates.kreditLabel}):',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted)),
                        Text(
                          CurrencyFormatter.formatRupiah(Money.rupiah(_estimatedMonthlyInterest)),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: titleDark,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 14, color: AppColors.primaryBorder),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Estimasi Angsuran / Bulan:',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: titleDark)),
                              const SizedBox(height: 2),
                              Text('Estimasi angsuran bersifat indikatif (tenor $_selectedTenor bln)',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 10, color: textMuted, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          CurrencyFormatter.formatRupiah(Money.rupiah(_estimatedMonthlyInstallment)),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: royalBlue,
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitApplication,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2A66),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Kirim Pengajuan Kredit',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
