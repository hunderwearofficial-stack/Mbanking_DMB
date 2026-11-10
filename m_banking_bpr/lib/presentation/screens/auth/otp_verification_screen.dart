import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  // Colors aligned with DMB Mobile Brand
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderColor = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _startTimer();
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
          backgroundColor: const Color(0xFFDC2626),
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
          backgroundColor: const Color(0xFFDC2626),
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
    return '${phone.substring(0, 8)}****';
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
                  // Top Bar: Back Button & Bank Logo
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: titleDark, size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Image.asset(
                          'assets/images/bank_logo.png',
                          height: 38,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Center Icon
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
                    ),
                    child: const Icon(Icons.mark_email_read_rounded, color: dmbGreen, size: 28),
                  ),

                  const SizedBox(height: 16),

                  // Title: Verifikasi OTP
                  const Text(
                    'Verifikasi Kode OTP',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Masked phone info
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: RichText(
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
                  ),

                  const SizedBox(height: 28),

                  // 6 OTP Digit Boxes
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
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isFilled ? primaryNavy : borderColor,
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            digit,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: titleDark,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),

                  // Countdown Timer & Resend
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _secondsLeft > 0
                        ? Text(
                            'Kirim ulang kode dalam 00:${_secondsLeft.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12.5, color: textMuted),
                          )
                        : TextButton(
                            onPressed: _startTimer,
                            child: const Text(
                              'Kirim Ulang Kode OTP',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: dmbGreen,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                  ),

                  const Spacer(),

                  // Keypad
                  _buildCustomKeypad(),

                  const SizedBox(height: 16),
                ],
              ),
            ),
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
