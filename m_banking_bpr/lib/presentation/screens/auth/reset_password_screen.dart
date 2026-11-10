import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String sessionId;
  const ResetPasswordScreen({super.key, this.sessionId = ''});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  // Colors aligned with DMB Mobile Brand
  static const Color primaryNavy = Color(0xFF0B356D); // Official Deep Navy Blue
  static const Color dmbGreen = Color(0xFF16984B); // Vibrant DMB Green
  static const Color titleDark = Color(0xFF0B2546); // Executive Headline Navy
  static const Color textMuted = Color(0xFF64748B); // Slate Muted
  static const Color borderColor = Color(0xFFE2E8F0); // Subtle Border

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onUpdatePassword() async {
    final p1 = _passwordController.text.trim();
    final p2 = _confirmPasswordController.text.trim();

    if (p1.isEmpty) {
      _showError('Password baru wajib diisi');
      return;
    }

    if (p1.length < 8) {
      _showError('Password minimal harus 8 karakter');
      return;
    }

    if (p1 != p2) {
      _showError('Konfirmasi password tidak cocok');
      return;
    }

    if (widget.sessionId.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final authRepo = context.read<AuthCubit>().authRepository;
        await authRepo.resetForgotPassword(
          sessionId: widget.sessionId,
          newPassword: p1,
        );
      } on ApiException catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showError(e.message);
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showError('Gagal memperbarui password: $e');
        }
        return;
      }
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Kata sandi berhasil diperbarui! Silakan masuk kembali.')),
          ],
        ),
        backgroundColor: dmbGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
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

                          // Title: Buat Sandi Baru
                          const Text(
                            'Buat Kata Sandi Baru',
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
                            'Silakan buat kata sandi baru minimal 8 karakter untuk keamanan akses akun Mobile Banking Anda.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: textMuted,
                              height: 1.45,
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Field 1: Password Baru
                          const Text(
                            'Kata Sandi Baru (Min. 8 Karakter)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 8),
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
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Minimal 8 karakter',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF4A607A),
                                  size: 22,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Field 2: Konfirmasi Password
                          const Text(
                            'Konfirmasi Kata Sandi Baru',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 8),
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
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Ketik ulang kata sandi baru',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF4A607A),
                                  size: 22,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscureConfirm = !_obscureConfirm),
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Action Button: Simpan Kata Sandi Baru →
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _onUpdatePassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryNavy,
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
                                          'Simpan Kata Sandi Baru',
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(Icons.check_circle_outline_rounded, size: 18),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Cancel Link
                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'Batal dan Kembali',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textMuted,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

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
