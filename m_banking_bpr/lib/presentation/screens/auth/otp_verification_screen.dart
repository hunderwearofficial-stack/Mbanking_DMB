import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';
import 'reset_password_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String sessionId;
  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.sessionId,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  String _otp = '';
  late String _activeSessionId;
  int _secondsLeft = 60;
  Timer? _timer;
  bool _isVerifying = false;
  bool _isResending = false;

  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;

  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.sessionId.trim();
    if (_activeSessionId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppToast.showError(
          context,
          'Sesi verifikasi tidak valid. Silakan ulangi proses dari awal.',
          title: 'Sesi Tidak Valid',
        );
        Navigator.of(context).maybePop();
      });
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft > 0) {
        setState(() {
          _secondsLeft--;
        });
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onKeyTap(String key) {
    if (_isVerifying || _isResending) return;
    if (_otp.length < 6) {
      setState(() {
        _otp += key;
      });
      if (_otp.length == 6) {
        _verifyOtpCode(_otp);
      }
    }
  }

  Future<void> _handleResendOtp() async {
    if (_isResending || _isVerifying) return;
    setState(() => _isResending = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      final res = await authRepo.requestForgotPassword(phoneNumber: widget.phoneNumber);
      if (!mounted) return;
      final newSession = (res['session_id'] ?? '').toString().trim();
      setState(() {
        if (newSession.isNotEmpty) {
          _activeSessionId = newSession;
        }
        _otp = '';
        _isResending = false;
      });
      _startTimer();
      AppToast.showSuccess(
        context,
        'Kode OTP baru telah dikirimkan ke nomor handphone Anda.',
        title: 'OTP Dikirim Ulang',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResending = false);
      AppToast.showError(
        context,
        ApiException.humanize(
          e,
          fallback: 'Gagal mengirim ulang kode OTP. Silakan coba kembali.',
        ),
        title: 'Gagal Mengirim OTP',
      );
    }
  }

  Future<void> _verifyOtpCode(String code) async {
    if (_activeSessionId.isEmpty) {
      AppToast.showError(
        context,
        'Sesi verifikasi tidak valid. Silakan ulangi proses dari awal.',
        title: 'Sesi Tidak Valid',
      );
      Navigator.of(context).maybePop();
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      await authRepo.verifyForgotPasswordOtp(
        sessionId: _activeSessionId,
        otpCode: code,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(sessionId: _activeSessionId),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _otp = '';
        _isVerifying = false;
      });
      AppToast.showError(context, ApiException.humanize(e), title: 'Kode OTP Tidak Valid');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otp = '';
        _isVerifying = false;
      });
      AppToast.showError(
        context,
        ApiException.humanize(
          e,
          fallback: 'Verifikasi OTP gagal. Silakan coba kembali.',
        ),
        title: 'Gagal Verifikasi',
      );
    }
  }

  void _onBackspace() {
    if (_otp.isNotEmpty && !_isVerifying) {
      setState(() {
        _otp = _otp.substring(0, _otp.length - 1);
      });
    }
  }

  String _maskPhone(String phone) {
    final len = phone.length;
    if (len <= 4) return phone;
    if (len <= 8) return '${phone.substring(0, 3)}****';
    return '${phone.substring(0, 4)}****${phone.substring(len - 3)}';
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
        body: Column(
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
                  padding: const EdgeInsets.fromLTRB(14, 8, 22, 20),
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
                              height: 40,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.mark_email_read_rounded,
                                color: Color(0xFF34D399),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'KEAMANAN AKUN',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF34D399),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Verifikasi Kode OTP',
                                    style: TextStyle(
                                      fontSize: 20,
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
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
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
                  children: [
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        text: 'Kode verifikasi telah dikirim melalui SMS ke ',
                        style: const TextStyle(fontSize: 13, color: textMuted, height: 1.4),
                        children: [
                          TextSpan(
                            text: _maskPhone(widget.phoneNumber),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: titleDark),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (index) {
                        final isFilled = index < _otp.length;
                        final digit = isFilled ? _otp[index] : '';

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 42,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFilled ? const Color(0xFF0A2A66) : Colors.transparent,
                              width: 1.8,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              digit,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: titleDark,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 16),

                    _secondsLeft > 0
                        ? Text(
                            'Kirim ulang kode dalam 00:${_secondsLeft.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12.5, color: textMuted),
                          )
                        : TextButton.icon(
                            onPressed: _isResending ? null : _handleResendOtp,
                            icon: _isResending
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: dmbGreen),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 16, color: dmbGreen),
                            label: Text(
                              _isResending ? 'Mengirim Ulang...' : 'Kirim Ulang Kode OTP',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: dmbGreen,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            _buildCustomKeypad(),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'backspace'],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: row.map((key) {
                if (key.isEmpty) {
                  return const SizedBox(width: 70, height: 48);
                } else if (key == 'backspace') {
                  return SizedBox(
                    width: 70,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.backspace_outlined, size: 22, color: titleDark),
                      onPressed: _onBackspace,
                    ),
                  );
                } else {
                  return SizedBox(
                    width: 70,
                    height: 48,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _onKeyTap(key),
                      child: Center(
                        child: Text(
                          key,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: titleDark,
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
