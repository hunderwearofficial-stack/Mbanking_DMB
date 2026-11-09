import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/custom_button.dart';
import '../home/home_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  int _currentStep = 1; // 1: Rekening, 2: OTP, 3: Password & PIN
  bool _isLoading = false;

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
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
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
        _sessionId = res['session_id'] as String? ?? '';
        _maskedPhone = res['masked_phone'] as String? ?? phone;
        _fullName = res['full_name'] as String? ?? 'Nasabah';
        _currentStep = 2;
      });
      _startOtpTimer();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Gagal memverifikasi data rekening: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== STEP 2: VERIFIKASI OTP ====================
  Future<void> _handleStep2Submit() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showError('Masukkan 6 digit kode OTP verifikasi');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthCubit>().authRepository;
      final ok = await authRepo.verifyActivationOtp(
        sessionId: _sessionId,
        otpCode: otp,
      );

      if (ok) {
        setState(() {
          _currentStep = 3;
        });
      } else {
        _showError('Kode OTP tidak valid');
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Gagal memverifikasi OTP: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== STEP 3: SETUP PASSWORD & PIN ====================
  Future<void> _handleStep3Submit() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (password.length < 8) {
      _showError('Password minimal harus 8 karakter');
      return;
    }
    if (password != confirmPassword) {
      _showError('Konfirmasi password tidak cocok');
      return;
    }
    if (pin.length != 6) {
      _showError('PIN transaksi harus tepat 6 digit angka');
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

      // Notify AuthCubit & AccountCubit
      if (mounted) {
        context.read<AuthCubit>().checkAuthStatus();
        context.read<AccountCubit>().loadDashboardData();
        _showSuccessDialog(authResponse.user.fullName);
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Aktivasi gagal: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 44),
            ),
            const SizedBox(height: 18),
            Text(
              'Aktivasi Berhasil!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              'Selamat datang, $name.\nAkun M-Banking Bank DMB Anda telah aktif dan terikat aman dengan perangkat ini.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
                child: const Text('Mulai Bertransaksi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Aktivasi M-Banking',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () {
            if (_currentStep > 1) {
              setState(() => _currentStep--);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // STEP PROGRESS HEADER
            _buildStepIndicator(),

            // SCROLLABLE STEP FORM
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildCurrentStepContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    Widget buildStepCircle(int step, String label) {
      final isActive = _currentStep == step;
      final isDone = _currentStep > step;

      return Expanded(
        child: Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDone
                    ? AppColors.primary
                    : isActive
                        ? const Color(0xFFE0F2FE)
                        : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDone || isActive ? AppColors.primary : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : Text(
                        '$step',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isActive ? AppColors.primary : const Color(0xFF64748B),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive || isDone ? FontWeight.w700 : FontWeight.w500,
                color: isActive || isDone ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          buildStepCircle(1, 'Data Rekening'),
          Container(width: 24, height: 2, color: _currentStep > 1 ? AppColors.primary : const Color(0xFFE2E8F0)),
          buildStepCircle(2, 'Verifikasi OTP'),
          Container(width: 24, height: 2, color: _currentStep > 2 ? AppColors.primary : const Color(0xFFE2E8F0)),
          buildStepCircle(3, 'Password & PIN'),
        ],
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
        // Hero Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aktivasi Nasabah Bank DMB',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF166534)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Masukkan data rekening tabungan fisik Anda yang terdaftar di kantor cabang.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF15803D), height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Input 1: Nomor Rekening
        const Text(
          'Nomor Rekening Tabungan / CIF',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _accountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Masukkan Nomor Rekening atau CIF',
            prefixIcon: const Icon(Icons.wallet_rounded, color: Color(0xFF94A3B8), size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 18),

        // Input 2: Nomor Handphone
        const Text(
          'Nomor Handphone Terdaftar',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Masukkan Nomor Handphone Aktif',
            prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFF94A3B8), size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '* Pastikan nomor handphone aktif untuk menerima kode OTP verifikasi SMS/WA.',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 28),

        CustomButton(
          text: 'Verifikasi Rekening',
          isLoading: _isLoading,
          backgroundColor: AppColors.primary,
          onPressed: _handleStep1Submit,
        ),
      ],
    );
  }

  // ==================== UI STEP 2 ====================
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
          child: const Icon(Icons.mark_email_read_rounded, color: Color(0xFF2563EB), size: 32),
        ),
        const SizedBox(height: 16),
        const Text(
          'Verifikasi Kode OTP',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 6),
        Text(
          'Kode 6 digit telah dikirimkan ke nomor handphone\n$_maskedPhone atas nama $_fullName',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
        ),
        const SizedBox(height: 24),

        // 6-digit OTP Input
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 12, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            counterText: '',
            hintText: '------',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
          ),
        ),
        const SizedBox(height: 16),

        // Demo OTP helper badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Text(
            'Kode OTP Demo: 123456',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
          ),
        ),
        const SizedBox(height: 20),

        // Countdown / Resend
        if (_otpCountdown > 0)
          Text(
            'Kirim ulang kode dalam $_otpCountdown detik',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          )
        else
          TextButton(
            onPressed: () {
              _startOtpTimer();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kode OTP baru telah dikirimkan'), behavior: SnackBarBehavior.floating),
              );
            },
            child: const Text('Kirim Ulang Kode OTP', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        const SizedBox(height: 24),

        CustomButton(
          text: 'Lanjutkan',
          isLoading: _isLoading,
          backgroundColor: AppColors.primary,
          onPressed: _handleStep2Submit,
        ),
      ],
    );
  }

  // ==================== UI STEP 3 ====================
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_rounded, color: Color(0xFF2563EB), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kredensial Keamanan Akun',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Buat password untuk login apps, dan PIN 6 digit untuk otorisasi transfer dana.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF), height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Field: Password Baru
        const Text('Password Baru (Min. 8 Karakter)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Minimal 8 karakter huruf & angka',
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF94A3B8), size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
        ),
        const SizedBox(height: 14),

        // Field: Konfirmasi Password
        const Text('Konfirmasi Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            hintText: 'Ulangi password baru',
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.lock_reset_rounded, color: Color(0xFF94A3B8), size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
        ),
        const SizedBox(height: 18),

        // Field: PIN Transaksi 6 Digit
        const Text('PIN Transaksi (6 Digit Angka)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: InputDecoration(
            counterText: '',
            hintText: '6 digit angka rahasia',
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.pin_rounded, color: Color(0xFF94A3B8), size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
        ),
        const SizedBox(height: 14),

        // Field: Konfirmasi PIN
        const Text('Konfirmasi PIN Transaksi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Ulangi 6 digit PIN',
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.pin_outlined, color: Color(0xFF94A3B8), size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
        ),
        const SizedBox(height: 24),

        CustomButton(
          text: 'Selesaikan Aktivasi',
          isLoading: _isLoading,
          backgroundColor: AppColors.primary,
          onPressed: _handleStep3Submit,
        ),
      ],
    );
  }
}

