import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/security/security_hardening_service.dart';
import '../../../core/security/session_inactivity_detector.dart';
import '../../../core/services/dynamic_config_service.dart';
import 'change_password_screen.dart';
import 'change_pin_screen.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  static const Color primaryNavy = AuthUiTokens.deepCobalt;
  static const Color royalBlue = AuthUiTokens.royalBlue;
  static const Color dmbGreen = Color(0xFF059669);
  static const Color titleDark = AuthUiTokens.titleDark;
  static const Color textMuted = AuthUiTokens.textMuted;
  static const Color borderLight = Color(0xFFE8EEF6);
  static const Color bgCanvas = AuthUiTokens.canvas;

  bool _flagSecureEnabled = true;
  bool _scanningRoot = false;
  RootInspectionResult? _rootResult;
  bool _biometricEnabled = false;
  BiometricCapability? _biometricCap;

  @override
  void initState() {
    super.initState();
    _loadSecurityStatus();
  }

  Future<void> _loadSecurityStatus() async {
    final flagSecure = await SecurityHardeningService.isFlagSecureEnabled();
    final root = await SecurityHardeningService.checkRootStatus();
    if (!mounted) return;
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
          AppToast.showSuccess(
            context,
            'Fitur Masuk Biometrik Berhasil Diaktifkan! Anda kini dapat masuk praktis dengan sensor perangkat.',
            title: 'Biometrik Aktif',
          );
        }
      } else {
        if (mounted) {
          AppToast.showError(
            context,
            res.errorMessage ?? 'Verifikasi biometrik dibatalkan.',
            title: 'Validasi Biometrik',
          );
        }
      }
    } else {
      await storage.clearBiometricCredentials();
      if (mounted) {
        setState(() => _biometricEnabled = false);
        AppToast.showInfo(
          context,
          'Fitur Masuk Biometrik Dinonaktifkan.',
          title: 'Pengaturan Biometrik',
        );
      }
    }
  }

  Future<void> _testBiometricSensor() async {
    final res = await BiometricAuthService.authenticate(
      reason: 'Pindai sidik jari atau wajah Anda untuk konfirmasi',
    );
    if (mounted) {
      if (res.success) {
        AppToast.showSuccess(
          context,
          'Sensor Berfungsi Normal! Perangkat Anda siap digunakan untuk masuk akun.',
          title: 'Pemeriksaan Sensor',
        );
      } else {
        AppToast.showError(
          context,
          res.errorMessage ?? 'Pemeriksaan sensor dibatalkan.',
          title: 'Pemeriksaan Sensor',
        );
      }
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
              _buildModalRow(
                'Integritas Keamanan',
                res.isRooted ? 'Tidak disarankan untuk layanan perbankan' : 'Terlindungi',
                isAlert: res.isRooted,
              ),
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
    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DmbPageHeader(
              title: 'Pengaturan Keamanan',
              subtitle: 'Perlindungan Akun & Privasi',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        color: AuthUiTokens.softBlueBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.dialpad_rounded, color: AuthUiTokens.deepCobalt, size: 22),
                    ),
                    title: Text(
                      'Ganti PIN 6 Digit',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleDark,
                      ),
                    ),
                    subtitle: Text(
                      'Ubah PIN untuk verifikasi data sensitif akun Anda',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, height: 1.3),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: textMuted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

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

                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    trailing: Icon(
                      _flagSecureEnabled ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: _flagSecureEnabled ? dmbGreen : textMuted,
                      size: 22,
                    ),
                    leading: Container(
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
                          ? 'Aktif (standar perbankan): tangkapan dan rekaman layar diblokir untuk menjaga kerahasiaan data Anda.'
                          : 'Tidak aktif pada versi pengembangan aplikasi ini.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted, height: 1.3),
                    ),
                  ),

                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),

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
                            DynamicConfigService().isServerConnected ? 'Terhubung' : 'Tidak Terhubung',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: DynamicConfigService().isServerConnected ? dmbGreen : textMuted,
                            ),
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
                      'Akun otomatis keluar jika tidak aktif selama ${SessionInactivityDetector.timeoutSeconds ~/ 60} menit demi menjaga keamanan data Anda.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted, height: 1.3),
                    ),
                    trailing: const Icon(Icons.check_circle_rounded, color: dmbGreen, size: 22),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

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
