import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/account_repository.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import '../deposit/deposit_application_bottom_sheet.dart';
import '../loan/loan_application_bottom_sheet.dart';
import 'application_status_screen.dart';

/// Bubble popover putih dengan panah kecil menunjuk ke tombol "Ajukan" (gaya BCA).
Future<void> showApplyBottomSheet(BuildContext context) {
  final screenW = MediaQuery.of(context).size.width;
  // Tab ke-2 dari 4 tab (pusat tab berada di ~37.5% lebar layar)
  final tabCenterX = screenW * 0.375;
  const double boxWidth = 185;
  final double leftOffset = (tabCenterX - boxWidth / 2).clamp(16.0, screenW - boxWidth - 16.0);
  final double arrowLeftInBox = (tabCenterX - leftOffset - 8).clamp(18.0, boxWidth - 34.0);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black.withOpacity(0.45),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogCtx, _, __) {
      return SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: leftOffset,
              bottom: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.white,
                    elevation: 10,
                    shadowColor: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: boxWidth,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BubbleMenuRow(
                            icon: Icons.credit_card_outlined,
                            label: 'Kredit',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const LoanCategoryApplyScreen()),
                              );
                            },
                          ),
                          _BubbleMenuRow(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'Tabungan',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SavingsApplicationScreen()),
                              );
                            },
                          ),
                          _BubbleMenuRow(
                            icon: Icons.savings_outlined,
                            label: 'Deposito',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const DepositTenorApplyScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: arrowLeftInBox),
                    child: CustomPaint(
                      size: const Size(16, 9),
                      painter: _BubbleArrowPainter(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _BubbleMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BubbleMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryNavy, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tab "Ajukan" di Menu Bar bawah (shortcut Kredit, Tabungan, Deposito)
class ApplyHubScreen extends StatelessWidget {
  const ApplyHubScreen({super.key});

  static const Color _navy = AppColors.primaryNavy;
  static const Color _titleDark = AppColors.titleDark;
  static const Color _textMuted = AppColors.textMuted;
  static const Color _border = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    return _dmbApplyScaffold(
      title: 'Ajukan Produk',
      subtitle: 'Pilih produk simpanan atau pembiayaan Bank DMB',
      showBack: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'PILIH PRODUK PENGAJUAN',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                _CleanMenuTile(
                  icon: Icons.credit_card_outlined,
                  title: 'Ajukan Kredit',
                  subtitle: 'KKM, Micro Individual Loan (MIL), Kredit Multi Guna (KMG)',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoanCategoryApplyScreen()),
                  ),
                ),
                const Divider(height: 1, indent: 52, endIndent: 16, color: Color(0xFFF1F5F9)),
                _CleanMenuTile(
                  icon: Icons.savings_outlined,
                  title: 'Ajukan Deposito',
                  subtitle: 'Pilihan tenor 1, 3, 6, dan 12 Bulan',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DepositTenorApplyScreen()),
                  ),
                ),
                const Divider(height: 1, indent: 52, endIndent: 16, color: Color(0xFFF1F5F9)),
                _CleanMenuTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Ajukan Tabungan',
                  subtitle: 'Pembukaan rekening Tabungan Bank DMB',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SavingsApplicationScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'PEMANTAUAN',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: _CleanMenuTile(
              icon: Icons.assignment_outlined,
              iconColor: _navy,
              title: 'Status Pengajuan',
              subtitle: 'Pantau status Diajukan, Proses, dan Selesai',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ApplicationStatusScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pilihan Ajukan Kredit: KKM, MIL, KMG -> e-form
class LoanCategoryApplyScreen extends StatelessWidget {
  const LoanCategoryApplyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        title: 'Kredit Kelompok Mandiri (KKM)',
        subtitle: 'Pembiayaan kelompok KKM Reguler & KILAT KKM',
        productName: 'Kredit Kelompok Mandiri (KKM)',
        icon: Icons.people_outline_rounded,
      ),
      (
        title: 'Micro Individual Loan (MIL)',
        subtitle: 'Modal kerja usaha mikro perorangan',
        productName: 'Micro Individual Loan (MIL)',
        icon: Icons.storefront_outlined,
      ),
      (
        title: 'Kredit Multi Guna (KMG)',
        subtitle: 'Pembiayaan serbaguna & kebutuhan konsumtif',
        productName: 'Kredit Multi Guna (KMG)',
        icon: Icons.description_outlined,
      ),
    ];

    return _dmbApplyScaffold(
      title: 'Ajukan Kredit',
      subtitle: 'Pilih fasilitas pinjaman sesuai kebutuhan Anda',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'PILIH JENIS KREDIT',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: List.generate(options.length, (i) {
                final o = options[i];
                return Column(
                  children: [
                    _CleanMenuTile(
                      icon: o.icon,
                      title: o.title,
                      subtitle: o.subtitle,
                      onTap: () => LoanApplicationBottomSheet.show(
                        context,
                        initialProductName: o.productName,
                      ),
                    ),
                    if (i < options.length - 1)
                      const Divider(height: 1, indent: 52, endIndent: 16, color: Color(0xFFF1F5F9)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pilihan Ajukan Deposito: 1, 3, 6, 12 Bulan -> e-form
class DepositTenorApplyScreen extends StatelessWidget {
  const DepositTenorApplyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tenors = [
      (months: 1, label: 'Deposito 1 Bulan', desc: 'Tenor singkat dengan fleksibilitas tinggi'),
      (months: 3, label: 'Deposito 3 Bulan', desc: 'Pilihan jangka pendek-menengah'),
      (months: 6, label: 'Deposito 6 Bulan', desc: 'Imbal hasil optimal di atas rata-rata pasar'),
      (months: 12, label: 'Deposito 12 Bulan', desc: 'Imbal hasil maksimal & dijamin LPS'),
    ];

    return _dmbApplyScaffold(
      title: 'Ajukan Deposito',
      subtitle: 'Pilih jangka waktu simpanan berjangka',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'PILIH JANGKA WAKTU',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: List.generate(tenors.length, (i) {
                final t = tenors[i];
                return Column(
                  children: [
                    _CleanMenuTile(
                      icon: Icons.savings_outlined,
                      title: t.label,
                      subtitle: t.desc,
                      onTap: () => DepositApplicationBottomSheet.show(
                        context,
                        initialTenorMonths: t.months,
                      ),
                    ),
                    if (i < tenors.length - 1)
                      const Divider(height: 1, indent: 52, endIndent: 16, color: Color(0xFFF1F5F9)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// E-Form Ajukan Tabungan -> submit ke /api/v1/applications (product_type: TABUNGAN)
class SavingsApplicationScreen extends StatefulWidget {
  const SavingsApplicationScreen({super.key});

  @override
  State<SavingsApplicationScreen> createState() => _SavingsApplicationScreenState();
}

class _SavingsApplicationScreenState extends State<SavingsApplicationScreen> {
  final _amountCtrl = TextEditingController(text: '100000');
  final _purposeCtrl = TextEditingController();
  String _selectedProduct = 'Tabungan Mandiri DMB';
  bool _isSubmitting = false;

  static const _products = [
    'Tabungan Mandiri DMB',
    'Tabungan Simpel DMB',
    'Tabungan Rencana DMB',
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountVal = int.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (amountVal < 50000) {
      AppToast.showError(context, 'Setoran awal minimal Rp 50.000');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await context.read<AccountRepository>().submitProductApplication(
            productType: 'TABUNGAN',
            productName: _selectedProduct,
            amount: Money.rupiah(amountVal),
            tenorMonths: 1,
            interestRate: '-',
            purposeOrSource: _purposeCtrl.text.trim().isEmpty
                ? 'Pembukaan Tabungan Baru'
                : _purposeCtrl.text.trim(),
          );
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppToast.showSuccess(
        context,
        'Pengajuan pembukaan tabungan berhasil dikirim.',
        title: 'Pengajuan Terkirim',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppToast.showError(
        context,
        ApiException.humanize(e, fallback: 'Gagal mengirim pengajuan tabungan.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _dmbApplyScaffold(
      title: 'Ajukan Tabungan',
      subtitle: 'Pembukaan rekening tabungan Bank DMB',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produk Tabungan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.titleDark,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedProduct,
                  isExpanded: true,
                  items: _products.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedProduct = v);
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Rencana Setoran Awal (Min. Rp 50.000)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.titleDark,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tujuan Pembukaan (Opsional)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.titleDark,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _purposeCtrl,
                  decoration: InputDecoration(
                    hintText: 'Contoh: Tabungan usaha / pribadi',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Kirim Pengajuan',
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _dmbApplyScaffold({
  required String title,
  required String subtitle,
  bool showBack = true,
  required Widget body,
}) {
  return AuthSwooshCanvas(
    child: SafeArea(
      bottom: false,
      child: Column(
        children: [
          DmbPageHeader(
            title: title,
            subtitle: subtitle,
            showBack: showBack,
          ),
          Expanded(child: body),
        ],
      ),
    ),
  );
}

class _CleanMenuTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CleanMenuTile({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? AppColors.primaryNavy, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.titleDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
