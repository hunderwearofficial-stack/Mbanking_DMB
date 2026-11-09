import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import 'reset_password_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String sessionId;
  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.sessionId = '',
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  String _otp = '';
  int _secondsLeft = 60;
  Timer? _timer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
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
    if (_isVerifying) return;
    if (_otp.length < 6) {
      setState(() {
        _otp += key;
      });
      if (_otp.length == 6) {
        _verifyOtpCode(_otp);
      }
    }
  }

  Future<void> _verifyOtpCode(String code) async {
    if (widget.sessionId.isEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(sessionId: widget.sessionId)),
      );
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      await authRepo.verifyForgotPasswordOtp(
        sessionId: widget.sessionId,
        otpCode: code,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(sessionId: widget.sessionId),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _otp = '';
        _isVerifying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otp = '';
        _isVerifying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verifikasi OTP gagal: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onBackspace() {
    if (_otp.isNotEmpty) {
      setState(() {
        _otp = _otp.substring(0, _otp.length - 1);
      });
    }
  }

  String _maskPhone(String phone) {
    if (phone.length <= 6) return phone;
    return '${phone.substring(0, 9)}****';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'One Time Password',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Title from Figma
            const Text(
              'Masukkan Kode OTP',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle with masked phone
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: 'Kami telah mengirimkan SMS berisi kode OTP ke ',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  children: [
                    TextSpan(
                      text: _maskPhone(widget.phoneNumber),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 6 OTP Input Boxes matching Figma
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final isFilled = index < _otp.length;
                final digit = isFilled ? _otp[index] : '';

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 44,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFilled ? AppColors.primary : const Color(0xFF16984B).withOpacity(0.5),
                      width: 1.8,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      digit,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // Countdown Resend Timer matching Figma
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: 'Belum terima OTP? ',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  children: [
                    TextSpan(
                      text: _secondsLeft > 0
                          ? 'Kirim ulang dalam 00:${_secondsLeft.toString().padLeft(2, '0')}'
                          : 'Kirim Ulang Sekarang',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),

            // Custom Keypad from Figma
            _buildFigmaKeypad(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFigmaKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['bio', '0', 'backspace'],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: row.map((key) {
                if (key == 'bio') {
                  return const SizedBox(
                    width: 70,
                    height: 50,
                  );
                } else if (key == 'backspace') {
                  return SizedBox(
                    width: 70,
                    height: 50,
                    child: IconButton(
                      icon: const Icon(Icons.backspace_outlined, size: 24, color: AppColors.textPrimary),
                      onPressed: _onBackspace,
                    ),
                  );
                } else {
                  return SizedBox(
                    width: 70,
                    height: 50,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(25),
                      onTap: () => _onKeyTap(key),
                      child: Center(
                        child: Text(
                          key,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
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

