import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import 'otp_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  // Colors aligned with DMB Mobile Brand
  static const Color primaryNavy = Color(0xFF0B356D); // Official Deep Navy Blue
  static const Color dmbGreen = Color(0xFF16984B); // Vibrant DMB Green
  static const Color titleDark = Color(0xFF0B2546); // Executive Headline Navy
  static const Color textMuted = Color(0xFF64748B); // Slate Muted
  static const Color borderColor = Color(0xFFE2E8F0); // Subtle Border

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onSendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showToast('Nomor handphone wajib diisi', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      final res = await authRepo.requestForgotPassword(phoneNumber: phone);
      final sessionId = res['session_id'] as String? ?? '';
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            phoneNumber: phone,
            sessionId: sessionId,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showToast(e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      _showToast('Gagal mengirim OTP: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFDC2626) : dmbGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Background Mount Salak & Tugu Kujang Artwork
            Positioned.fill(
              child: Image.asset(
                'assets/images/splash_artwork.jpg',
                fit: BoxFit.cover,
              ),
            ),

            // 2. White Soft Wash Gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.20, 0.32, 0.85, 1.0],
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.40),
                      Colors.white.withOpacity(0.95),
                      Colors.white.withOpacity(0.98),
                      Colors.white.withOpacity(0.20),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Foreground Content Layer
            SafeArea(
              child: Column(
                children: [
                  // Top Bar: Back Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: titleDark, size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable Body
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Center Official DMB Mobile Logo
                          Center(
                            child: Image.asset(
                              'assets/images/bank_logo.png',
                              height: 60,
                              fit: BoxFit.contain,
                            ),
                          ),

                          const SizedBox(height: 26),

                          // Title: Lupa PIN / Password
                          const Text(
                            'Lupa PIN / Kata Sandi',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              color: titleDark,
                              letterSpacing: -0.4,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Subtitle Description
                          const Text(
                            'Masukkan nomor handphone yang terdaftar pada akun Mobile Banking Anda untuk menerima kode verifikasi OTP.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: textMuted,
                              height: 1.45,
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Input Label
                          const Text(
                            'Nomor Handphone Terdaftar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: titleDark,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Input Field: Nomor Handphone (Radius 16)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Contoh: 081234567890',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                                prefixIcon: const Icon(
                                  Icons.phone_android_rounded,
                                  color: Color(0xFF4A607A),
                                  size: 22,
                                ),
                                suffixIcon: _phoneController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.cancel_rounded,
                                            color: Color(0xFF94A3B8), size: 18),
                                        onPressed: () => setState(() => _phoneController.clear()),
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 14, color: dmbGreen),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Pastikan nomor handphone aktif untuk menerima SMS kode OTP.',
                                  style: TextStyle(fontSize: 11.5, color: textMuted),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Primary Action Button: Kirim Kode OTP →
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _onSendOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryNavy, // Deep Royal Navy Blue
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shadowColor: primaryNavy.withOpacity(0.35),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Kirim Kode OTP',
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded, size: 18),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Secondary Link Back to Login
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'Ingat kata sandi akun Anda? ',
                                  style: TextStyle(fontSize: 13, color: textMuted),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: const Text(
                                    'Masuk Sekarang',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: dmbGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 48),

                          // Bottom Security Notice
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.shield_outlined, size: 16, color: primaryNavy),
                                SizedBox(width: 6),
                                Text(
                                  'Transaksi Anda aman bersama DMB',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
