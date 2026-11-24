import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import 'otp_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;

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
      final sessionId = (res['session_id'] ?? '').toString();
      if (!mounted) return;
      if (sessionId.isEmpty) {
        _showToast('Sesi verifikasi belum dapat dibuat. Silakan coba kembali.', isError: true);
        return;
      }
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
      _showToast(ApiException.humanize(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      _showToast(
        ApiException.humanize(
          e,
          fallback: 'Permintaan kode OTP belum dapat diproses. Periksa koneksi internet Anda.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (isError) {
      AppToast.showError(context, msg, title: 'Validasi Data');
    } else {
      AppToast.showSuccess(context, msg);
    }
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
              eyebrow: 'PEMULIHAN AKSES',
              title: 'Lupa Kata Sandi',
              icon: Icons.lock_reset_rounded,
            ),

            // Main White Card
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: AuthSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Verifikasi Nomor Terdaftar',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AuthUiTokens.titleDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Masukkan nomor handphone yang terdaftar pada akun Mobile Banking Anda untuk menerima kode verifikasi OTP.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AuthUiTokens.textMuted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AuthUiTokens.softBlueBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AuthUiTokens.softBlueBorder),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: AuthUiTokens.royalBlue,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pengaturan PIN 6 digit dapat dilakukan setelah Anda masuk melalui menu Profil > Pengaturan Keamanan.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AuthUiTokens.titleDark,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      'Nomor Handphone Terdaftar',
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
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AuthUiTokens.titleDark,
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
                            color: AuthUiTokens.royalBlue,
                            size: 20,
                          ),
                          suffixIcon: _phoneController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.cancel_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 18,
                                  ),
                                  onPressed: () => setState(() => _phoneController.clear()),
                                )
                              : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pastikan nomor handphone aktif untuk menerima SMS kode OTP.',
                      style: TextStyle(fontSize: 11.5, color: AuthUiTokens.textMuted),
                    ),

                    const SizedBox(height: 22),

                    AuthGradientButton(
                      label: 'Kirim Kode OTP',
                      onPressed: _isLoading ? null : _onSendOtp,
                      isLoading: _isLoading,
                    ),

                    const SizedBox(height: 16),

                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Ingat kata sandi akun Anda? ',
                            style: TextStyle(fontSize: 13, color: AuthUiTokens.textMuted),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Masuk',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AuthUiTokens.royalBlue,
                              ),
                            ),
                          ),
                        ],
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
    );
  }
}
