import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  final _oldPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _oldPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    if (isError) {
      AppToast.showError(context, message, title: 'Validasi Kata Sandi');
    } else {
      AppToast.showSuccess(context, message);
    }
  }

  bool _hasLettersAndNumbers(String input) {
    final hasUpper = RegExp(r'[A-Z]').hasMatch(input);
    final hasNumber = RegExp(r'[0-9]').hasMatch(input);
    return hasUpper && hasNumber;
  }

  void _onValidateAndConfirm() {
    final oldPw = _oldPwController.text.trim();
    final newPw = _newPwController.text.trim();
    final confPw = _confirmPwController.text.trim();

    if (oldPw.isEmpty) {
      _showToast('Kata sandi saat ini wajib diisi', isError: true);
      return;
    }
    if (newPw.length < 6) {
      _showToast('Kata sandi baru minimal harus 6 karakter', isError: true);
      return;
    }
    if (!_hasLettersAndNumbers(newPw)) {
      _showToast('Kata sandi baru wajib mengandung huruf kapital dan angka (contoh: Indo123)', isError: true);
      return;
    }
    if (oldPw == newPw) {
      _showToast('Kata sandi baru tidak boleh sama dengan kata sandi lama', isError: true);
      return;
    }
    if (newPw != confPw) {
      _showToast('Konfirmasi kata sandi baru tidak cocok', isError: true);
      return;
    }

    _showConfirmationDialog(oldPw, newPw);
  }

  void _showConfirmationDialog(String oldPw, String newPw) {
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
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_reset_rounded, color: royalBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Konfirmasi Perubahan Sandi',
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
          'Apakah Anda yakin ingin memperbarui kata sandi login akun Mobile Banking Anda?',
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
              _onSubmitChangePassword(oldPw, newPw);
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

  Future<void> _onSubmitChangePassword(String oldPw, String newPw) async {
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthCubit>().authRepository.changePassword(
            oldPassword: oldPw,
            newPassword: newPw,
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
          fallback: 'Kata sandi belum dapat diperbarui. Silakan coba kembali.',
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
              'Kata Sandi Berhasil Diubah!',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kata sandi login Anda telah berhasil diperbarui dengan aman. Silakan gunakan kata sandi baru untuk masuk berikutnya.',
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
              'Ganti Kata Sandi Login',
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
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset_rounded, color: royalBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pembaruan Kata Sandi Terotorisasi',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: titleDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Verifikasi kata sandi saat ini dan tanda tangan kriptografis perangkat terdaftar Anda.',
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
          'Kata Sandi Saat Ini',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _oldPwController,
          obscureText: _obscureOld,
          style: GoogleFonts.plusJakartaSans(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Masukkan kata sandi saat ini',
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: royalBlue, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureOld ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: textMuted,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureOld = !_obscureOld),
            ),
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
          'Kata Sandi Baru',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _newPwController,
          obscureText: _obscureNew,
          style: GoogleFonts.plusJakartaSans(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Minimal 6 karakter (Contoh: Indo123)',
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
            prefixIcon: const Icon(Icons.vpn_key_outlined, color: royalBlue, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: textMuted,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
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
          'Konfirmasi Kata Sandi Baru',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPwController,
          obscureText: _obscureConfirm,
          style: GoogleFonts.plusJakartaSans(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Ketik ulang kata sandi baru Anda',
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
            prefixIcon: const Icon(Icons.verified_user_outlined, color: royalBlue, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: textMuted,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
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
                'Ketentuan Keamanan Sandi:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),
              _buildRequirementRow('Minimal 6 karakter, huruf kapital & angka (contoh: Indo123)'),
              const SizedBox(height: 5),
              _buildRequirementRow('Tidak sama dengan kata sandi saat ini'),
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
                        'Simpan Kata Sandi Baru',
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
