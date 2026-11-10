import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_exception.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../home/home_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  int _currentStep = 1; // 1: Rekening, 2: OTP, 3: Password & PIN
  bool _isLoading = false;

  // Colors aligned with DMB Mobile Executive Design
  static const Color primaryNavy = Color(0xFF0B356D); // Official Deep Navy Blue
  static const Color dmbGreen = Color(0xFF16984B); // Vibrant DMB Green
  static const Color titleDark = Color(0xFF0B2546); // Executive Headline Navy
  static const Color textMuted = Color(0xFF64748B); // Slate Muted
  static const Color borderColor = Color(0xFFE2E8F0); // Subtle Border

  // Step 1 Controllers
  final _accountController = TextEditingController();
  final _phoneController = TextEditingController();

  // Step 2 Controllers
  final _otpController = TextEditingController();
  String _sessionId = '';
  String _maskedPhone = '';
  String _fullName = '';
  int _otpCountdown = 60;
  Timer? _countdownTimer;

  // Step 3 Controllers
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
    _accountController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ==================== STEP 1: VERIFIKASI REKENING ====================
  Future<void> _handleStep1Submit() async {
    final accountNo = _accountController.text.trim();
    final phone = _phoneController.text.trim();

    if (accountNo.isEmpty) {
      _showError('Nomor rekening tabungan wajib diisi');
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
        phoneNumber: phone,
      );

      setState(() {
        _sessionId = res['session_id'] ?? '';
        _maskedPhone = res['masked_phone'] ?? phone;
        _fullName = res['full_name'] ?? '';
        _currentStep = 2;
        _isLoading = false;
      });
      _startOtpTimer();
    } on ApiException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Terjadi kesalahan koneksi. Silakan coba beberapa saat lagi.');
    }
  }

  // ==================== STEP 2: VERIFIKASI OTP ====================
  Future<void> _handleStep2Submit() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showError('Kode OTP harus 6 digit');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      await authRepo.verifyActivationOtp(
        sessionId: _sessionId,
        otpCode: otp,
      );

      setState(() {
        _currentStep = 3;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Verifikasi OTP gagal. Silakan periksa kembali kode Anda.');
    }
  }

  // ==================== STEP 3: BUAT PASSWORD & PIN ====================
  Future<void> _handleStep3Submit() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (password.length < 8) {
      _showError('Kata sandi minimal 8 karakter');
      return;
    }
    if (password != confirmPassword) {
      _showError('Konfirmasi kata sandi tidak cocok');
      return;
    }
    if (pin.length != 6) {
      _showError('PIN transaksi harus 6 digit angka');
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
        password: password,
        pin: pin,
      );

      setState(() => _isLoading = false);

      if (mounted) {
        context.read<AuthCubit>().checkAuthStatus();
        final name = authResponse.user.fullName.isNotEmpty
            ? authResponse.user.fullName
            : _fullName;
        _showSuccessDialog(name);
      }
    } on ApiException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Aktivasi gagal. Silakan coba kembali.');
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
                  color: const Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
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
                'Selamat datang, $name.\nAkun Mobile Banking Bank DMB Anda telah aktif dan siap digunakan untuk bertransaksi.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: textMuted, height: 1.45),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    elevation: 2,
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  },
                  child: const Text(
                    'Mulai Bertransaksi',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                  // Top Bar: Back & Step Indicator
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: titleDark, size: 24),
                          onPressed: () {
                            if (_currentStep > 1) {
                              setState(() => _currentStep--);
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                        Image.asset(
                          'assets/images/bank_logo.png',
                          height: 38,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 40), // Balance spacing
                      ],
                    ),
                  ),

                  // Modern Segmented Step Indicator
                  _buildStepIndicator(),

                  // Scrollable Form
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCurrentStepContent(),
                          const SizedBox(height: 32),

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

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
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
          const SizedBox(height: 10),
          Text(
            _currentStep == 1
                ? 'Langkah 1: Verifikasi Nomor Rekening'
                : (_currentStep == 2
                    ? 'Langkah 2: Verifikasi Kode OTP'
                    : 'Langkah 3: Buat Kata Sandi & PIN'),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: titleDark,
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
      bgColor = const Color(0xFF0761DB);
      content = const Icon(Icons.check_rounded, size: 16, color: Colors.white);
    } else if (isCurrent) {
      bgColor = const Color(0xFF0761DB);
      content = Text(
        '$step',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
    } else {
      bgColor = const Color(0xFFE2E8F2);
      content = Text(
        '$step',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: const Color(0xFF0761DB).withOpacity(0.28),
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
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isPassed ? const Color(0xFF0761DB) : const Color(0xFFD3DBE8),
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

  // ==================== UI STEP 1 ====================
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
          'Masukkan nomor rekening dan nomor handphone terdaftar Anda di Bank DMB untuk memulai aktivasi.',
          style: TextStyle(
            fontSize: 13.5,
            color: textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),

        // Input 1: Nomor Rekening
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
            controller: _accountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
            decoration: const InputDecoration(
              hintText: 'Contoh: 1001002003',
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
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Input 2: Nomor Handphone
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
              color: Color(0xFF0F172A),
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

        // Action Button: Verifikasi Rekening →
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryNavy,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: primaryNavy.withOpacity(0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
            onPressed: _isLoading ? null : _handleStep1Submit,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Verifikasi Rekening',
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
      ],
    );
  }

  // ==================== UI STEP 2 ====================
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
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
        const Text(
          'Verifikasi Kode OTP',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: titleDark),
        ),
        const SizedBox(height: 8),
        Text(
          'Kode 6 digit telah dikirimkan ke nomor handphone\n$_maskedPhone atas nama $_fullName',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: textMuted, height: 1.45),
        ),
        const SizedBox(height: 28),

        // 6-digit OTP Input
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
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Countdown / Resend
        if (_otpCountdown > 0)
          Text(
            'Kirim ulang kode dalam $_otpCountdown detik',
            style: const TextStyle(fontSize: 12.5, color: textMuted),
          )
        else
          TextButton(
            onPressed: () {
              _startOtpTimer();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kode OTP baru telah dikirimkan ke nomor Anda'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text(
              'Kirim Ulang Kode OTP',
              style: TextStyle(fontWeight: FontWeight.w700, color: dmbGreen, fontSize: 13.5),
            ),
          ),
        const SizedBox(height: 32),

        // Action Button: Lanjutkan →
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryNavy,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: primaryNavy.withOpacity(0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
            onPressed: _isLoading ? null : _handleStep2Submit,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Lanjutkan',
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
      ],
    );
  }

  // ==================== UI STEP 3 ====================
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
          'Buat kata sandi untuk masuk aplikasi, dan PIN 6 digit untuk otorisasi transaksi finansial Anda.',
          style: TextStyle(
            fontSize: 13.5,
            color: textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),

        // Input 1: Kata Sandi Baru
        const Text(
          'Kata Sandi Baru (Min. 8 Karakter)',
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
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF64748B),
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Input 2: Konfirmasi Kata Sandi
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
              color: Color(0xFF0F172A),
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
                  color: const Color(0xFF64748B),
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Input 3: PIN 6 Digit
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
                  color: const Color(0xFF64748B),
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Input 4: Konfirmasi PIN 6 Digit
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
                  color: const Color(0xFF64748B),
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirmPin = !_obscureConfirmPin),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Action Button: Selesaikan Aktivasi →
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryNavy,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: primaryNavy.withOpacity(0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
            onPressed: _isLoading ? null : _handleStep3Submit,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Selesaikan Aktivasi',
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
      ],
    );
  }
}
