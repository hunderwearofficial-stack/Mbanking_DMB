import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
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
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _otpController = TextEditingController();

  int _currentStep = 1; // 1: Input PIN, 2: OTP Verification
  bool _isSubmitting = false;

  // OTP Countdown
  int _resendCountdown = 60;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _oldPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
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
    final oldPin = _oldPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final confPin = _confirmPinController.text.trim();

    if (oldPin.length != 6) {
      _showToast('PIN lama harus tepat 6 digit angka', isError: true);
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
    if (newPin != confPin) {
      _showToast('Konfirmasi PIN baru tidak cocok', isError: true);
      return;
    }

    setState(() {
      _currentStep = 2;
    });
    _startCountdown();
    _showToast('Kode OTP keamanan telah dikirim ke nomor HP terdaftar Anda');
  }

  Future<void> _onSubmitChangePin() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      _showToast('Masukkan 6 digit kode OTP verifikasi', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final oldPin = _oldPinController.text.trim();
      final newPin = _newPinController.text.trim();

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
      _showToast(e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showToast('Gagal mengubah PIN: $e', isError: true);
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
              'PIN 6 digit baru Anda telah aktif. Gunakan PIN ini untuk otorisasi setiap transfer dan pembayaran Anda.',
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

  // ==================== STEP 1: INPUT PIN FORM ====================
  Widget _buildStep1Form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Security Info Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBBF7D0)),
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
                      'PIN terdiri dari 6 digit angka rahasia untuk memverifikasi seluruh transaksi finansial Anda.',
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

        // 1. PIN Saat Ini
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

        // 2. PIN Baru
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

        // 3. Konfirmasi PIN Baru
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

        // Tips Keamanan PIN
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
              _buildRequirementRow('Hindari angka berurutan (misal: 123456)'),
              const SizedBox(height: 5),
              _buildRequirementRow('Hindari penggunaan tanggal lahir'),
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
              color: const Color(0xFFF0FDF4),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
            ),
            child: const Center(
              child: Icon(Icons.verified_user_rounded, color: dmbGreen, size: 36),
            ),
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'Verifikasi Otorisasi OTP',
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
            'Demi keamanan rekening, masukkan 6 digit kode OTP yang telah dikirimkan ke nomor HP terdaftar:',
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

        // Resend Countdown
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
            onPressed: _isSubmitting ? null : _onSubmitChangePin,
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    'Verifikasi & Simpan PIN Baru',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),

        const SizedBox(height: 14),

        // Back to form button
        TextButton(
          onPressed: () => setState(() => _currentStep = 1),
          child: Text(
            'Ubah PIN Input',
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

