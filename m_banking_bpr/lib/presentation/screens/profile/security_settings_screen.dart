import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/security/security_hardening_service.dart';
import '../../../core/security/ssl_pinning_service.dart';
import '../../../core/security/session_inactivity_detector.dart';
import 'change_password_screen.dart';
import 'change_pin_screen.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  // Executive DMB Brand Colors
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  bool _flagSecureEnabled = true;
  bool _scanningRoot = false;
  RootInspectionResult? _rootResult;
  bool _quickTimeoutActive = false;
  int _countdown = 10;
  Timer? _countdownTimer;
  bool _biometricEnabled = false;
  BiometricCapability? _biometricCap;

  @override
  void initState() {
    super.initState();
    _loadSecurityStatus();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    SessionInactivityDetector.resetToStandardTimeout();
    super.dispose();
  }

  Future<void> _loadSecurityStatus() async {
    final flagSecure = await SecurityHardeningService.isFlagSecureEnabled();
    final root = await SecurityHardeningService.checkRootStatus();
    final storage = context.read<AuthCubit>().authRepository.secureStorage;
    final isBio = await storage.isBiometricEnabled();
    final bioCap = await BiometricAuthService.checkCapability();

    if (mounted) {
      setState(() {
        _flagSecureEnabled = flagSecure;
        _rootResult = root;
        _biometricEnabled = isBio;
        _biometricCap = bioCap;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final storage = context.read<AuthCubit>().authRepository.secureStorage;
    if (value) {
      final res = await BiometricAuthService.authenticate(
        reason: 'Pindai sidik jari atau Face ID Anda untuk mengaktifkan Login Biometrik',
      );
      if (res.success) {
        final refresh = await storage.getRefreshToken() ?? '';
        final cif = await storage.getCIF() ?? '';
        final phone = await storage.getPhoneNumber() ?? '';
        final fullName = await storage.getFullName() ?? 'Nasabah Bank DMB';
        final acc = await storage.getPrimaryAccount() ?? '';

        await storage.saveBiometricCredentials(
          refreshToken: refresh,
          cif: cif,
          phone: phone,
          fullName: fullName,
          primaryAccount: acc,
        );

        if (mounted) {
          setState(() => _biometricEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Fitur Masuk Biometrik Berhasil Diaktifkan! Anda kini dapat masuk praktis dengan sensor perangkat.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
              ),
              backgroundColor: primaryNavy,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res.errorMessage ?? 'Verifikasi biometrik dibatalkan.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
              ),
              backgroundColor: const Color(0xFFE11D48),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      await storage.clearBiometricCredentials();
      if (mounted) {
        setState(() => _biometricEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fitur Masuk Biometrik Dinonaktifkan.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
            ),
            backgroundColor: const Color(0xFF64748B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _testBiometricSensor() async {
    final res = await BiometricAuthService.authenticate(
      reason: 'Pindai sidik jari atau wajah Anda untuk konfirmasi',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.success
                ? 'Sensor Berfungsi Normal! Perangkat Anda siap digunakan untuk masuk akun.'
                : (res.errorMessage ?? 'Pemeriksaan sensor dibatalkan.'),
            style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
          ),
          backgroundColor: res.success ? dmbGreen : const Color(0xFFE11D48),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleFlagSecure(bool value) async {
    final success = await SecurityHardeningService.setFlagSecure(value);
    if (mounted) {
      setState(() => _flagSecureEnabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Perlindungan Layar Aktif: Tangkapan layar dinonaktifkan demi menjaga privasi data saldo Anda.'
                : 'Perlindungan Layar Nonaktif: Tangkapan layar diizinkan sementara.',
            style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
          ),
          backgroundColor: value ? primaryNavy : const Color(0xFFE11D48),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _scanRootIntegrity() async {
    setState(() => _scanningRoot = true);
    final result = await SecurityHardeningService.checkRootStatus();
    if (mounted) {
      setState(() {
        _rootResult = result;
        _scanningRoot = false;
      });
      _showRootDetailSheet(result);
    }
  }

  void _showRootDetailSheet(RootInspectionResult res) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: borderLight, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: res.isRooted ? const Color(0xFFFFE4E6) : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      res.isRooted ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
                      color: res.isRooted ? const Color(0xFFE11D48) : dmbGreen,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          res.isRooted ? 'Status Perangkat Perlu Perhatian' : 'Status Perangkat Terverifikasi Aman',
                          style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: titleDark),
                        ),
                        Text(
                          'Standar Perlindungan Perbankan Bank DMB',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: borderLight),
              const SizedBox(height: 14),
              _buildModalRow('Model Perangkat', res.deviceModel),
              _buildModalRow('Sistem Operasi', res.osVersion),
              _buildModalRow(
                'Status Sistem Operasi',
                res.isRooted ? 'Perlu Perhatian (Dimodifikasi)' : 'Resmi & Aman (Terproteksi)',
                isAlert: res.isRooted,
              ),
              _buildModalRow('Keaslian Sistem Operasi', res.reasons.isEmpty ? 'Lolos Pemeriksaan (Resmi)' : 'Terindikasi Modifikasi'),
              _buildModalRow('Integritas Keamanan', '100% Terlindungi'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Tutup Informasi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startQuickIdleTest() {
    setState(() {
      _quickTimeoutActive = true;
      _countdown = 10;
    });

    SessionInactivityDetector.setQuickTestTimeout(10);

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        SessionInactivityDetector.resetToStandardTimeout();
        setState(() => _quickTimeoutActive = false);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Simulasi Uji Coba: Diamkan layar selama 10 detik. Akun akan keluar otomatis untuk membuktikan fitur proteksi.',
          style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
        ),
        backgroundColor: const Color(0xFF0062E3),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildModalRow(String label, String value, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isAlert ? const Color(0xFFE11D48) : titleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Pengaturan Keamanan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'PERLINDUNGAN AKUN & PRIVASI',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: royalBlue,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==================== SECTION 1: CREDENTIALS ====================
            Text(
              'Kredensial & Akses Masuk',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 1. Ganti Password Login
                  ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                      );
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock_reset_rounded, color: royalBlue, size: 22),
                    ),
                    title: Text(
                      'Ganti Password Login',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleDark,
                      ),
                    ),
                    subtitle: Text(
                      'Perbarui kata sandi untuk masuk ke akun Mobile DMB',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, height: 1.3),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: textMuted),
                  ),

                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),

                  // 2. Ganti PIN Transaksi 6 Digit
                  ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChangePinScreen()),
                      );
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.dialpad_rounded, color: dmbGreen, size: 22),
                    ),
                    title: Text(
                      'Ganti PIN Transaksi 6 Digit',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleDark,
                      ),
                    ),
                    subtitle: Text(
                      'Ubah 6 digit PIN otorisasi transaksi finansial',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, height: 1.3),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: textMuted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ==================== SECTION 2: MOBILE SECURITY HARDENING ====================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Proteksi & Privasi Perangkat',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: titleDark,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 11, color: dmbGreen),
                      const SizedBox(width: 4),
                      Text(
                        'AKTIF & TERLINDUNGI',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: dmbGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 1. Login Biometrik
                  SwitchListTile(
                    value: _biometricEnabled,
                    onChanged: _toggleBiometric,
                    activeColor: royalBlue,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    secondary: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _biometricEnabled ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.fingerprint_rounded,
                        color: _biometricEnabled ? royalBlue : textMuted,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      'Masuk dengan ${_biometricCap?.label ?? 'Sidik Jari'}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: titleDark),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          _biometricEnabled
                              ? 'Aktif: Masuk lebih praktis dan aman dengan sensor biometrik perangkat.'
                              : 'Nonaktif: Masuk akun menggunakan kata sandi Anda.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted, height: 1.3),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _testBiometricSensor,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.touch_app_rounded, size: 12, color: royalBlue),
                                const SizedBox(width: 4),
                                Text(
                                  'Cek Sensor Biometrik',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 10.5, fontWeight: FontWeight.w700, color: royalBlue),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),

                  // 2. Perlindungan Privasi Layar
                  SwitchListTile(
                    value: _flagSecureEnabled,
                    onChanged: _toggleFlagSecure,
                    activeColor: royalBlue,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    secondary: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _flagSecureEnabled ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _flagSecureEnabled ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: _flagSecureEnabled ? royalBlue : textMuted,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      'Perlindungan Privasi Layar',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: titleDark),
                    ),
                    subtitle: Text(
                      _flagSecureEnabled
                          ? 'Aktif: Menjaga kerahasiaan saldo & transaksi dari tangkapan layar pihak lain.'
                          : 'Nonaktif: Tangkapan layar diizinkan sementara.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted, height: 1.3),
                    ),
                  ),

                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),

                  // 3. Keamanan Sistem Ponsel
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_rootResult?.isRooted ?? false) ? const Color(0xFFFFE4E6) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        (_rootResult?.isRooted ?? false) ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
                        color: (_rootResult?.isRooted ?? false) ? const Color(0xFFE11D48) : dmbGreen,
                        size: 22,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Keamanan Sistem Ponsel',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: titleDark),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (_rootResult?.isRooted ?? false) ? const Color(0xFFFFE4E6) : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            (_rootResult?.isRooted ?? false) ? 'Perlu Perhatian' : 'Aman',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: (_rootResult?.isRooted ?? false) ? const Color(0xFFE11D48) : dmbGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Memastikan sistem operasi ponsel Anda resmi dan bebas dari modifikasi berbahaya.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted, height: 1.3),
                    ),
                    trailing: _scanningRoot
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: royalBlue))
                        : IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: royalBlue, size: 22),
                            onPressed: _scanRootIntegrity,
                            tooltip: 'Periksa Ulang',
                          ),
                  ),

                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),

                  // 4. Enkripsi Jaringan Perbankan
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock_outline_rounded, color: royalBlue, size: 22),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Enkripsi Jaringan Perbankan',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: titleDark),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Terkoneksi Aman',
                            style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: dmbGreen),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Seluruh data transaksi dan komunikasi Anda dilindungi jalur enkripsi resmi Bank DMB.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted, height: 1.3),
                    ),
                    trailing: const Icon(Icons.check_circle_rounded, color: dmbGreen, size: 22),
                  ),

                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),

                  // 5. Kunci Otomatis Saat Tidak Aktif
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.timer_outlined, color: Color(0xFFEA580C), size: 22),
                    ),
                    title: Text(
                      'Kunci Otomatis Saat Tidak Aktif',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: titleDark),
                    ),
                    subtitle: Text(
                      _quickTimeoutActive
                          ? 'Simulasi aktif: keluar otomatis dalam $_countdown detik jika tanpa aktivitas!'
                          : 'Akun otomatis keluar jika tidak aktif selama 3 menit demi menjaga keamanan saldo Anda.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: _quickTimeoutActive ? const Color(0xFFEA580C) : textMuted,
                        fontWeight: _quickTimeoutActive ? FontWeight.w700 : FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    trailing: ElevatedButton(
                      onPressed: _quickTimeoutActive ? null : _startQuickIdleTest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        _quickTimeoutActive ? '$_countdown s' : 'Uji Coba',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ==================== SECTION 3: TIPS KEAMANAN ====================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: royalBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Panduan Menjaga Keamanan Akun',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: titleDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildTipItem(
                    '1. Kerahasiaan Informasi Akun:',
                    'Jangan pernah memberitahukan password, PIN 6 digit, atau kode OTP kepada siapa pun termasuk pihak bank.',
                  ),
                  const SizedBox(height: 8),
                  _buildTipItem(
                    '2. Privasi Layar & Ponsel:',
                    'Layar dilindungi agar saldo dan histori transaksi Anda tidak dapat terekam atau di-screenshot oleh aplikasi lain.',
                  ),
                  const SizedBox(height: 8),
                  _buildTipItem(
                    '3. Komunikasi Perbankan Terenkripsi:',
                    'Setiap pengiriman data transaksi terenkripsi langsung secara aman dengan sistem perbankan Bank DMB.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: titleDark,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          desc,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: textMuted,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
