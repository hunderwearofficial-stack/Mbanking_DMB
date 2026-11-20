import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String sessionId;
  const ResetPasswordScreen({super.key, required this.sessionId});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderColor = AppColors.borderLight;

  @override
  void initState() {
    super.initState();
    if (widget.sessionId.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppToast.showError(
          context,
          'Sesi verifikasi tidak valid. Silakan ulangi proses dari awal.',
          title: 'Sesi Tidak Valid',
        );
        Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _hasLettersAndNumbers(String input) {
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(input);
    final hasNumber = RegExp(r'[0-9]').hasMatch(input);
    return hasLetter && hasNumber;
  }

  Future<void> _onUpdatePassword() async {
    final sessionId = widget.sessionId.trim();
    if (sessionId.isEmpty) {
      _showError('Sesi verifikasi tidak valid. Silakan ulangi proses dari awal.');
      Navigator.of(context).maybePop();
      return;
    }

    final p1 = _passwordController.text.trim();
    final p2 = _confirmPasswordController.text.trim();

    if (p1.isEmpty) {
      _showError('Kata sandi baru wajib diisi');
      return;
    }

    if (p1.length < 8) {
      _showError('Kata sandi minimal harus 8 karakter');
      return;
    }

    if (!_hasLettersAndNumbers(p1)) {
      _showError('Kata sandi wajib mengandung kombinasi huruf dan angka');
      return;
    }

    if (p1 != p2) {
      _showError('Konfirmasi kata sandi tidak cocok');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      await authRepo.resetForgotPassword(
        sessionId: sessionId,
        newPassword: p1,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(ApiException.humanize(e));
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(ApiException.humanize(
          e,
          fallback: 'Kata sandi belum dapat diperbarui. Silakan coba kembali.',
        ));
      }
      return;
    }
    if (mounted) setState(() => _isLoading = false);

    if (!mounted) return;
    AppToast.showSuccess(
      context,
      'Kata sandi berhasil diperbarui! Silakan masuk kembali.',
      title: 'Reset Sandi Berhasil',
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showError(String msg) {
    AppToast.showError(context, msg, title: 'Validasi Kata Sandi');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFF6F6F2),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F2),
        body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A2A66), Color(0xFF0D3882)],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: ContentImage(
                                'app.logo',
                                height: 42,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.key_rounded,
                                  color: Color(0xFF34D399),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ATUR ULANG SANDI',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF34D399),
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Buat Kata Sandi Baru',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gunakan minimal 8 karakter dengan kombinasi huruf dan angka untuk menjaga keamanan akun Anda.',
                        style: TextStyle(
                          fontSize: 13,
                          color: textMuted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'Kata Sandi Baru',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: titleDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Minimal 8 karakter kombinasi',
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: textMuted,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

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
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ketik ulang kata sandi baru',
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: textMuted,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _onUpdatePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A2A66),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
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
                              : const Text(
                                  'Simpan Kata Sandi Baru',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  AppContent.text('login.footer'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
