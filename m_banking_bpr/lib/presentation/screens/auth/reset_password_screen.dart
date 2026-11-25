import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
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

  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;

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
    final hasUpper = RegExp(r'[A-Z]').hasMatch(input);
    final hasNumber = RegExp(r'[0-9]').hasMatch(input);
    return hasUpper && hasNumber;
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

    if (p1.length < 6) {
      _showError('Kata sandi minimal harus 6 karakter');
      return;
    }

    if (!_hasLettersAndNumbers(p1)) {
      _showError('Kata sandi wajib mengandung huruf kapital dan angka (contoh: Indo123)');
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
    return AuthSwooshCanvas(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTopHeader(
              onBack: () => Navigator.of(context).pop(),
              eyebrow: 'ATUR ULANG SANDI',
              title: 'Buat Kata Sandi Baru',
              icon: Icons.key_rounded,
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: AuthSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gunakan minimal 6 karakter dengan huruf kapital dan angka (contoh: Indo123).',
                      style: TextStyle(
                        fontSize: 13,
                        color: AuthUiTokens.textMuted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'Kata Sandi Baru',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AuthUiTokens.titleDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AuthUiTokens.inputFill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AuthUiTokens.inputBorder),
                      ),
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AuthUiTokens.titleDark,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Minimal 6 karakter (Contoh: Indo123)',
                          hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            color: AuthUiTokens.royalBlue,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AuthUiTokens.textMuted,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Konfirmasi Kata Sandi Baru',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AuthUiTokens.titleDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AuthUiTokens.inputFill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AuthUiTokens.inputBorder),
                      ),
                      child: TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AuthUiTokens.titleDark,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ketik ulang kata sandi baru',
                          hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          prefixIcon: const Icon(
                            Icons.verified_user_outlined,
                            color: AuthUiTokens.royalBlue,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AuthUiTokens.textMuted,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    AuthGradientButton(
                      label: 'Simpan Kata Sandi Baru',
                      onPressed: _isLoading ? null : _onUpdatePassword,
                      isLoading: _isLoading,
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
                            color: AuthUiTokens.textMuted,
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
                  color: AuthUiTokens.textMuted,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
