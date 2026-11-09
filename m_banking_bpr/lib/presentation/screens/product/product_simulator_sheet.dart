import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';

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
  late String _selectedType;
  double _amount = 25000000;
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

  double get _annualRate => _selectedType == 'DEPOSITO' ? 0.0625 : 0.15; // 6.25% p.a Deposito, 15% p.a (1.25%/bln) Kredit

  double get _estimatedCalculation {
    if (_selectedType == 'DEPOSITO') {
      // Gross interest for tenor, minus 20% PPh tax
      final gross = _amount * (_annualRate / 12) * _tenorMonths;
      return gross * 0.80;
    } else {
      // Monthly installment (principal + flat interest)
      final principalPerMonth = _amount / _tenorMonths;
      final interestPerMonth = _amount * (_annualRate / 12);
      return principalPerMonth + interestPerMonth;
    }
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
        interestRate: isDeposito ? '6.25% p.a.' : '1.25% flat/bln',
        estimatedReturn: _estimatedCalculation,
        purposeOrSource: _purposeController.text.trim().isEmpty
            ? (isDeposito ? 'Dana Tabungan Mandiri DMB' : 'Modal Usaha Produktif')
            : _purposeController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDeposito
                ? 'Pengajuan Deposito Berjangka berhasil dikirim! Petugas CS Bank DMB akan segera memproses.'
                : 'Pengajuan Pinjaman berhasil dikirim! Tim Kredit Bank DMB akan segera menghubungi Anda.',
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      setState(() => _submitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (e) {
      setState(() => _submitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim pengajuan: $e'), backgroundColor: AppColors.danger),
      );
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
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Wondr Segmented Pill Switcher (Deposito vs Pinjaman)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedType = 'DEPOSITO';
                          _tenorMonths = 6;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isDeposito ? AppColors.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'Deposito Berjangka',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isDeposito ? Colors.white : AppColors.textSecondary,
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !isDeposito ? const Color(0xFFEA580C) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'Simulasi Pinjaman',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: !isDeposito ? Colors.white : AppColors.textSecondary,
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

              // Nominal Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isDeposito ? 'Nominal Penempatan Deposito' : 'Plafon Pinjaman Diajukan',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  Text(
                    CurrencyFormatter.formatRupiah(_amount),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.primary),
                  ),
                ],
              ),
              Slider(
                value: _amount,
                min: 5000000,
                max: 250000000,
                divisions: 49,
                activeColor: isDeposito ? AppColors.primary : const Color(0xFFEA580C),
                onChanged: (val) => setState(() => _amount = val),
              ),
              const SizedBox(height: 8),

              // Tenor Selection Chips
              const Text(
                'Pilih Jangka Waktu (Tenor)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Row(
                children: tenors.map((t) {
                  final active = _tenorMonths == t;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Center(child: Text('$t Bln')),
                        selected: active,
                        selectedColor: isDeposito ? const Color(0xFFCCFBF1) : const Color(0xFFFFEDD5),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: active
                              ? (isDeposito ? const Color(0xFF0F766E) : const Color(0xFFEA580C))
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) => setState(() => _tenorMonths = t),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Live Calculation Result Card (Wondr Style)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDeposito
                        ? [const Color(0xFF00382E), const Color(0xFF00897B)]
                        : [const Color(0xFF1E293B), const Color(0xFF0F766E)],
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
                          isDeposito ? 'Estimasi Bunga Bersih (Net)' : 'Estimasi Angsuran / Bulan',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isDeposito ? 'Bunga 6.25% p.a. • Dijamin LPS' : 'Bunga 1.25% Flat / Bln',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      CurrencyFormatter.formatRupiah(_estimatedCalculation),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isDeposito
                          ? 'Total Dana + Bunga saat jatuh tempo ($_tenorMonths bln): ${CurrencyFormatter.formatRupiah(_amount + _estimatedCalculation)}'
                          : 'Plafon ${CurrencyFormatter.formatRupiah(_amount)} selama $_tenorMonths bulan',
                      style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.85)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _purposeController,
                decoration: InputDecoration(
                  labelText: isDeposito ? 'Sumber Dana / Catatan (Opsional)' : 'Tujuan Penggunaan Pinjaman / Agunan',
                  hintText: isDeposito ? 'Contoh: Debet Rekening Tabungan DMB' : 'Contoh: Tambahan Modal Usaha Toko',
                  prefixIcon: const Icon(Icons.edit_note_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDeposito ? AppColors.primary : const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _submitting ? null : _submitApplication,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    isDeposito ? 'Ajukan Pembukaan Deposito Sekarang' : 'Ajukan Fasilitas Pinjaman Sekarang',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
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

