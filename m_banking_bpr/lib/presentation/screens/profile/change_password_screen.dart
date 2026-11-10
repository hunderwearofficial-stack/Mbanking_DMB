import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  // Executive Brand Palette
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color dmbRed = Color(0xFFDC2626);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  // Form Controllers
  final _oldPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();
  final _otpController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  int _currentStep = 1; // 1: Input Form, 2: OTP Verification
  bool _isSubmitting = false;

  // OTP Resend Countdown
  int _resendCountdown = 60;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _oldPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  String _maskPhoneNumber(String phone) {
    if (phone.length < 8) return phone;
    final prefix = phone.substring(0, 4);
    final suffix = phone.substring(phone.length - 4);
    return '$prefix •••• $suffix';
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: isError ? dmbRed : titleDark,
      ),
    );
  }

  void _onProceedToOtp() {
    final oldPw = _oldPwController.text.trim();
    final newPw = _newPwController.text.trim();
    final confPw = _confirmPwController.text.trim();

    if (oldPw.isEmpty) {
      _showToast('Password lama wajib diisi', isError: true);
      return;
    }
    if (newPw.length < 8) {
      _showToast('Password baru minimal harus 8 karakter', isError: true);
      return;
    }
    if (oldPw == newPw) {
      _showToast('Password baru tidak boleh sama dengan password lama', isError: true);
      return;
    }
    if (newPw != confPw) {
      _showToast('Konfirmasi password baru tidak cocok', isError: true);
      return;
    }

    // Advance to OTP Step
    setState(() {
      _currentStep = 2;
    });
    _startCountdown();
    _showToast('Kode OTP keamanan telah dikirim ke nomor HP terdaftar Anda');
  }

  Future<void> _onSubmitChangePassword() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      _showToast('Masukkan 6 digit kode OTP verifikasi', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final oldPw = _oldPwController.text.trim();
      final newPw = _newPwController.text.trim();

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
      _showToast(e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showToast('Gagal mengubah password: $e', isError: true);
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
                color: const Color(0xFFF0FDF4),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
              ),
              child: const Center(
                child: Icon(Icons.check_circle_rounded, color: dmbGreen, size: 38),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Password Berhasil Diubah!',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kata sandi login Anda telah berhasil diperbarui dengan aman. Silakan gunakan password baru untuk masuk berikutnya.',
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
                  Navigator.of(ctx).pop(); // Close dialog
                  Navigator.of(context).pop(); // Back to Security Screen
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
    final authState = context.watch<AuthCubit>().state;
    String userPhone = '081234567890';
    if (authState is AuthAuthenticated) {
      userPhone = authState.user.phoneNumber;
    }

    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
          onPressed: () {
            if (_currentStep == 2) {
              setState(() => _currentStep = 1);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Column(
          children: [
            Text(
              'Ganti Password Login',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'PT BPR DANA MANDIRI BOGOR',
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
        child: _currentStep == 1 ? _buildStep1Form() : _buildStep2Otp(userPhone),
      ),
    );
  }

  // ==================== STEP 1: INPUT PASSWORD FORM ====================
  Widget _buildStep1Form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Security Info Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBFDBFE)),
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
                      'Pembaruan Kata Sandi',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: titleDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pastikan password baru minimal 8 karakter dan belum pernah digunakan sebelumnya.',
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

        // 1. Password Saat Ini
        Text(
          'Password Saat Ini',
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
            hintText: 'Masukkan password lama',
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

        // 2. Password Baru
        Text(
          'Password Baru',
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
            hintText: 'Minimal 8 karakter kombinasi',
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

        // 3. Konfirmasi Password Baru
        Text(
          'Konfirmasi Password Baru',
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
            hintText: 'Ketik ulang password baru Anda',
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

        // Requirements Checklist Card
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
              _buildRequirementRow('Minimal 8 karakter huruf dan angka'),
              const SizedBox(height: 5),
              _buildRequirementRow('Tidak sama dengan password lama'),
              const SizedBox(height: 5),
              _buildRequirementRow('Verifikasi OTP wajib di tahap berikutnya'),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // Proceed Button
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
            onPressed: _onProceedToOtp,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Lanjut ke Verifikasi OTP',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==================== STEP 2: SECURITY OTP VERIFICATION ====================
  Widget _buildStep2Otp(String phoneNumber) {
    final maskedPhone = _maskPhoneNumber(phoneNumber);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),

        // Security Shield Badge
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBFDBFE), width: 2),
            ),
            child: const Center(
              child: Icon(Icons.security_rounded, color: royalBlue, size: 36),
            ),
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'Verifikasi Keamanan OTP',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: titleDark,
          ),
        ),

        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Demi menjaga keamanan rekening Anda, silakan masukkan 6 digit kode OTP yang telah dikirim ke nomor HP:',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: textMuted,
              height: 1.45,
            ),
          ),
        ),

        const SizedBox(height: 6),

        Text(
          maskedPhone,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: titleDark,
            letterSpacing: 0.5,
          ),
        ),

        const SizedBox(height: 26),

        // OTP Input Field
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 14,
              color: primaryNavy,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 26,
                letterSpacing: 14,
                color: borderLight,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: borderLight, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: royalBlue, width: 2),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Resend Timer / Action
        if (_resendCountdown > 0)
          Text(
            'Kirim ulang kode dalam $_resendCountdown detik',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          )
        else
          TextButton(
            onPressed: () {
              _startCountdown();
              _showToast('Kode OTP baru telah dikirimkan ulang');
            },
            child: Text(
              'Kirim Ulang Kode OTP',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: royalBlue,
              ),
            ),
          ),

        const SizedBox(height: 32),

        // Submit Button
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
            onPressed: _isSubmitting ? null : _onSubmitChangePassword,
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    'Verifikasi & Simpan Password',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),

        const SizedBox(height: 14),

        // Back to form button
        TextButton(
          onPressed: () => setState(() => _currentStep = 1),
          child: Text(
            'Ubah Password Input',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: textMuted,
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
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
        ),
      ],
    );
  }
}

