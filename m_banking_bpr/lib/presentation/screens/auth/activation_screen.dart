import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import '../home/home_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  int _currentStep = 1; // 1: Rekening, 2: OTP, 3: Password & PIN
  bool _isLoading = false;
  bool _isResendingOtp = false;

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderColor = AppColors.borderLight;

  static const Set<String> _weakPins = {
    '000000',
    '111111',
    '222222',
    '333333',
    '444444',
    '555555',
    '666666',
    '777777',
    '888888',
    '999999',
    '123456',
    '654321',
    '121212',
    '112233',
  };

  final _cifController = TextEditingController();
  final _phoneController = TextEditingController();

  final _otpController = TextEditingController();
  String _sessionId = '';
  String _maskedPhone = '';
  String _fullName = '';
  int _otpCountdown = 60;
  Timer? _countdownTimer;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;

  @override
  void dispose() {
    _cifController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startOtpTimer() {
    _countdownTimer?.cancel();
    setState(() => _otpCountdown = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otpCountdown > 0) {
        setState(() => _otpCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  void _showError(String message) {
    AppToast.showError(context, message, title: 'Validasi Aktivasi');
  }

  Future<void> _handleStep1Submit() async {
    final accountNo = _cifController.text.trim();
    final phone = _phoneController.text.trim();

    if (accountNo.isEmpty) {
      _showError('Nomor Rekening Tabungan wajib diisi');
      return;
    }
    if (phone.isEmpty) {
      _showError('Nomor handphone terdaftar wajib diisi');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      final res = await authRepo.verifyActivationAccount(
        accountNumber: accountNo,
        cifNumber: accountNo,
        phoneNumber: phone,
      );

      if (!mounted) return;
      setState(() {
        _sessionId = (res['session_id'] ?? '').toString();
        _maskedPhone = (res['masked_phone'] ?? phone).toString();
        _currentStep = 2;
        _isLoading = false;
      });
      _startOtpTimer();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(ApiException.humanize(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(ApiException.humanize(
        e,
        fallback: 'Koneksi sedang bermasalah. Silakan coba kembali beberapa saat lagi.',
      ));
    }
  }

  Future<void> _handleResendOtp() async {
    if (_isResendingOtp) return;
    final accountNo = _cifController.text.trim();
    final phone = _phoneController.text.trim();
    setState(() => _isResendingOtp = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      final res = await authRepo.verifyActivationAccount(
        accountNumber: accountNo,
        cifNumber: accountNo,
        phoneNumber: phone,
      );
      if (!mounted) return;
      final newSession = (res['session_id'] ?? '').toString();
      setState(() {
        if (newSession.isNotEmpty) {
          _sessionId = newSession;
        }
        _maskedPhone = (res['masked_phone'] ?? _maskedPhone).toString();
        _otpController.clear();
        _isResendingOtp = false;
      });
      _startOtpTimer();
      AppToast.showSuccess(
        context,
        'Kode OTP baru telah dikirimkan ke nomor handphone terdaftar Anda.',
        title: 'OTP Dikirim Ulang',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResendingOtp = false);
      _showError(ApiException.humanize(
        e,
        fallback: 'Gagal mengirim ulang kode OTP. Silakan coba kembali.',
      ));
    }
  }

  Future<void> _handleStep2Submit() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showError('Kode OTP harus 6 digit');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      final res = await authRepo.verifyActivationOtp(
        sessionId: _sessionId,
        otpCode: otp,
      );

      if (!mounted) return;
      final suggested = (res['suggested_username'] as String?) ?? '';
      setState(() {
        _fullName = (res['full_name'] as String?) ?? '';
        if (suggested.isNotEmpty && _usernameController.text.isEmpty) {
          _usernameController.text = suggested;
        }
        _currentStep = 3;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(ApiException.humanize(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(ApiException.humanize(
        e,
        fallback: 'Verifikasi OTP belum berhasil. Silakan periksa kembali kode Anda.',
      ));
    }
  }

  bool _hasLettersAndNumbers(String input) {
    final hasUpper = RegExp(r'[A-Z]').hasMatch(input);
    final hasNumber = RegExp(r'[0-9]').hasMatch(input);
    return hasUpper && hasNumber;
  }

  Future<void> _handleStep3Submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (username.length < 4 || username.length > 30) {
      _showError('Username harus antara 4 sampai 30 karakter');
      return;
    }
    if (password.length < 6) {
      _showError('Kata sandi minimal 6 karakter');
      return;
    }
    if (!_hasLettersAndNumbers(password)) {
      _showError('Kata sandi wajib mengandung huruf kapital dan angka (contoh: Indo123)');
      return;
    }
    if (password != confirmPassword) {
      _showError('Konfirmasi kata sandi tidak cocok');
      return;
    }
    if (pin.length != 6) {
      _showError('PIN transaksi harus tepat 6 digit angka');
      return;
    }
    if (_weakPins.contains(pin)) {
      _showError('PIN terlalu mudah ditebak (hindari angka berulang atau berurutan seperti 123456 atau 111111)');
      return;
    }
    if (pin != confirmPin) {
      _showError('Konfirmasi PIN transaksi tidak cocok');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      final authResponse = await authRepo.completeActivation(
        sessionId: _sessionId,
        username: username,
        password: password,
        pin: pin,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      context.read<AuthCubit>().checkAuthStatus();
      final name = authResponse.user.fullName.isNotEmpty
          ? authResponse.user.fullName
          : _fullName;
      _showSuccessDialog(name);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(ApiException.humanize(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(ApiException.humanize(
        e,
        fallback: 'Aktivasi akun belum berhasil diproses. Silakan coba kembali.',
      ));
    }
  }

  void _showSuccessDialog(String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.successBorder, width: 1.5),
                ),
                child: const Icon(Icons.check_circle_rounded, color: dmbGreen, size: 40),
              ),
              const SizedBox(height: 18),
              const Text(
                'Aktivasi Berhasil!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: titleDark),
              ),
              const SizedBox(height: 8),
              Text(
                'Selamat datang${name.isNotEmpty ? ", $name" : ""}.\nAkun Mobile Banking Bank DMB Anda telah aktif dan siap digunakan.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: textMuted, height: 1.45),
              ),
              const SizedBox(height: 24),
              AuthGradientButton(
                label: 'Mulai Layanan Perbankan',
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthSwooshCanvas(
      navyHeaderHeight: 235,
      child: Column(
        children: [
          AuthTopHeader(
            onBack: () {
              if (_currentStep > 1) {
                setState(() => _currentStep--);
              } else {
                Navigator.of(context).pop();
              }
            },
            eyebrow: 'PENDAFTARAN NASABAH',
            title: 'Aktivasi Mobile Banking',
            icon: Icons.how_to_reg_rounded,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  _buildStepIndicator(),
                  const Divider(height: 22, color: AuthUiTokens.inputBorder),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCurrentStepContent(),
                          const SizedBox(height: 22),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              AppContent.text('app.footer'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AuthUiTokens.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              _buildStepNode(1),
              Expanded(child: _buildStepLine(1)),
              _buildStepNode(2),
              Expanded(child: _buildStepLine(2)),
              _buildStepNode(3),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currentStep == 1
                ? 'Langkah 1: Verifikasi Rekening & Nomor HP'
                : (_currentStep == 2
                    ? 'Langkah 2: Verifikasi Kode OTP'
                    : 'Langkah 3: Buat Kata Sandi & PIN'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AuthUiTokens.royalBlue,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepNode(int step) {
    final isCurrent = _currentStep == step;
    final isCompleted = _currentStep > step;

    Color bgColor;
    Widget content;

    if (isCompleted) {
      bgColor = AuthUiTokens.royalBlue;
      content = const Icon(Icons.check_rounded, size: 16, color: Colors.white);
    } else if (isCurrent) {
      bgColor = AuthUiTokens.azureBlue;
      content = Text(
        '$step',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      );
    } else {
      bgColor = const Color(0xFFE2E8F0);
      content = Text(
        '$step',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: isCurrent || isCompleted
            ? [
                BoxShadow(
                  color: AuthUiTokens.royalBlue.withOpacity(0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Center(child: content),
    );
  }

  Widget _buildStepLine(int afterStep) {
    final isPassed = _currentStep > afterStep;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 2.5,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isPassed ? AuthUiTokens.royalBlue : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          'Daftar & Aktivasi Akun',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: titleDark,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Masukkan Nomor Rekening Tabungan dan nomor handphone yang terdaftar di Bank DMB untuk memulai aktivasi.',
          style: TextStyle(
            fontSize: 13.5,
            color: textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Nomor Rekening Tabungan',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleDark),
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
            controller: _cifController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(20),
            ],
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              hintText: 'Masukkan Nomor Rekening Tabungan Anda',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFF4A607A),
                size: 22,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Nomor Handphone Terdaftar',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleDark),
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
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              hintText: 'Contoh: 081234567890',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.phone_android_rounded,
                color: Color(0xFF4A607A),
                size: 22,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: dmbGreen),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Pastikan nomor handphone aktif untuk menerima kode OTP verifikasi SMS.',
                style: TextStyle(fontSize: 11.5, color: textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        AuthGradientButton(
          label: 'Verifikasi Rekening',
          onPressed: _isLoading ? null : _handleStep1Submit,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: AuthUiTokens.softBlueBg,
            shape: BoxShape.circle,
            border: Border.all(color: AuthUiTokens.softBlueBorder, width: 1.5),
          ),
          child: const Icon(
            Icons.mark_email_read_rounded,
            color: AuthUiTokens.royalBlue,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Verifikasi Kode OTP',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: titleDark),
        ),
        const SizedBox(height: 8),
        Text(
          'Kode 6 digit telah dikirimkan ke nomor handphone\n$_maskedPhone',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: textMuted, height: 1.45),
        ),
        const SizedBox(height: 28),

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
            controller: _otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
              color: titleDark,
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '------',
              hintStyle: TextStyle(color: Color(0xFFCBD5E1), letterSpacing: 10),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (_otpCountdown > 0)
          Text(
            'Kirim ulang kode dalam $_otpCountdown detik',
            style: const TextStyle(fontSize: 12.5, color: textMuted),
          )
        else
          TextButton.icon(
            onPressed: _isResendingOtp ? null : _handleResendOtp,
            icon: _isResendingOtp
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AuthUiTokens.royalBlue,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AuthUiTokens.royalBlue,
                  ),
            label: Text(
              _isResendingOtp ? 'Mengirim Ulang...' : 'Kirim Ulang Kode OTP',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AuthUiTokens.royalBlue,
                fontSize: 13.5,
              ),
            ),
          ),
        const SizedBox(height: 32),

        AuthGradientButton(
          label: 'Lanjutkan',
          onPressed: _isLoading ? null : _handleStep2Submit,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          'Buat Sandi & PIN',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: titleDark,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Buat kata sandi (kombinasi huruf & angka) untuk masuk aplikasi, dan PIN 6 digit untuk otorisasi transaksi finansial Anda.',
          style: TextStyle(
            fontSize: 13.5,
            color: textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Username / ID Pengguna',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleDark),
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
            controller: _usernameController,
            keyboardType: TextInputType.text,
            autocorrect: false,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              hintText: 'Contoh: evi482',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                color: Color(0xFF4A607A),
                size: 22,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Disarankan otomatis berdasarkan nama Anda. Anda dapat mengubahnya sesuai keinginan (4–30 karakter).',
          style: TextStyle(fontSize: 11.5, color: textMuted, height: 1.3),
        ),
        const SizedBox(height: 18),

        const Text(
          'Kata Sandi Baru (Min. 6 Karakter, Huruf Kapital & Angka)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleDark),
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
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Contoh: Indo123',
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
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: textMuted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Konfirmasi Kata Sandi',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleDark),
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
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Ulangi kata sandi baru',
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
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: textMuted,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 20),

        const Text(
          'PIN Transaksi 6 Digit',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleDark),
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
            controller: _pinController,
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: titleDark,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), letterSpacing: 6),
              prefixIcon: const Icon(
                Icons.pin_outlined,
                color: Color(0xFF4A607A),
                size: 22,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: textMuted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Konfirmasi PIN Transaksi',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: titleDark),
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
            controller: _confirmPinController,
            obscureText: _obscureConfirmPin,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: titleDark,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), letterSpacing: 6),
              prefixIcon: const Icon(
                Icons.pin_outlined,
                color: Color(0xFF4A607A),
                size: 22,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPin
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: textMuted,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirmPin = !_obscureConfirmPin),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 32),

        AuthGradientButton(
          label: 'Selesaikan Aktivasi',
          onPressed: _isLoading ? null : _handleStep3Submit,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}
