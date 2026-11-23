import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  static const Set<String> _weakPins = {
    '000000',
    '111111',
    '222222',
    '333333',
    '444444',
    '555555',
    '666666',
    '777777',
    '888888',
    '999999',
    '123456',
    '654321',
    '121212',
    '112233',
  };

  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    if (isError) {
      AppToast.showError(context, message, title: 'Validasi PIN Transaksi');
    } else {
      AppToast.showSuccess(context, message);
    }
  }

  void _onValidateAndConfirm() {
    final oldPin = _oldPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final confPin = _confirmPinController.text.trim();

    if (oldPin.length != 6) {
      _showToast('PIN saat ini harus tepat 6 digit angka', isError: true);
      return;
    }
    if (newPin.length != 6) {
      _showToast('PIN baru harus tepat 6 digit angka', isError: true);
      return;
    }
    if (oldPin == newPin) {
      _showToast('PIN baru tidak boleh sama dengan PIN lama', isError: true);
      return;
    }
    if (_weakPins.contains(newPin)) {
      _showToast('PIN baru terlalu mudah ditebak (hindari angka berulang atau berurutan seperti 123456)', isError: true);
      return;
    }
    if (newPin != confPin) {
      _showToast('Konfirmasi PIN baru tidak cocok', isError: true);
      return;
    }

    _showConfirmationDialog(oldPin, newPin);
  }

  void _showConfirmationDialog(String oldPin, String newPin) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.dialpad_rounded, color: dmbGreen, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Konfirmasi Perubahan PIN',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin memperbarui PIN Transaksi 6 digit akun Mobile Banking Anda?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Batal',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: textMuted,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryNavy,
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              _onSubmitChangePin(oldPin, newPin);
            },
            child: Text(
              'Ya, Simpan',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmitChangePin(String oldPin, String newPin) async {
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthCubit>().authRepository.changePin(
            oldPin: oldPin,
            newPin: newPin,
          );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      _showSuccessDialog();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showToast(ApiException.humanize(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showToast(
        ApiException.humanize(
          e,
          fallback: 'PIN transaksi belum dapat diperbarui. Silakan coba kembali.',
        ),
        isError: true,
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.successLight,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.successBorder, width: 2),
              ),
              child: const Center(
                child: Icon(Icons.check_circle_rounded, color: dmbGreen, size: 38),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'PIN Transaksi Berhasil Diubah!',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'PIN 6 digit baru Anda telah aktif dan siap digunakan untuk otorisasi layanan perbankan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: textMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryNavy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Selesai',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
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
    final bankName = DynamicConfigService().config.bankName.toUpperCase();

    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Ganti PIN Transaksi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              bankName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: royalBlue,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.successLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.successBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.dialpad_rounded, color: dmbGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PIN Otorisasi Transaksi',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: titleDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PIN terdiri dari 6 digit angka rahasia dan diverifikasi langsung dengan kunci keamanan perangkat terdaftar Anda.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'PIN Transaksi Saat Ini (6 Digit)',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _oldPinController,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.plusJakartaSans(fontSize: 18, letterSpacing: 6, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 18, letterSpacing: 6, color: textMuted),
            prefixIcon: const Icon(Icons.lock_clock_outlined, color: royalBlue, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: royalBlue, width: 1.5),
            ),
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'PIN Transaksi Baru (6 Digit)',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _newPinController,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.plusJakartaSans(fontSize: 18, letterSpacing: 6, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 18, letterSpacing: 6, color: textMuted),
            prefixIcon: const Icon(Icons.pin_outlined, color: royalBlue, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: royalBlue, width: 1.5),
            ),
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'Konfirmasi PIN Transaksi Baru',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPinController,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.plusJakartaSans(fontSize: 18, letterSpacing: 6, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 18, letterSpacing: 6, color: textMuted),
            prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: royalBlue, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: royalBlue, width: 1.5),
            ),
          ),
        ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tips Keamanan PIN:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),
              _buildRequirementRow('Tepat 6 digit angka rahasia'),
              const SizedBox(height: 5),
              _buildRequirementRow('Hindari angka berulang atau berurutan (misal: 123456, 111111)'),
              const SizedBox(height: 5),
              _buildRequirementRow('Dilindungi tanda tangan keamanan perangkat terdaftar'),
            ],
          ),
        ),

        const SizedBox(height: 30),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: _isSubmitting ? null : _onValidateAndConfirm,
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Simpan PIN Transaksi Baru',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementRow(String text) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 15, color: dmbGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
          ),
        ),
      ],
    );
  }
}
