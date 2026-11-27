import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import '../account/account_info_screen.dart';
import '../auth/login_screen.dart';
import '../auth/terms_conditions_screen.dart';
import '../deposit/deposit_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../loan/loan_screen.dart';
import '../mutation/mutation_screen.dart';
import '../product/product_catalog_screen.dart';
import 'company_profile_screen.dart';
import 'security_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isTab;
  const ProfileScreen({super.key, this.isTab = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color dmbRed = AppColors.danger;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  late Future<Map<String, dynamic>> _profileFuture;
  bool _isDataMasked = true;
  Map<String, dynamic>? _revealedProfile;

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfileData();
  }

  Future<Map<String, dynamic>> _fetchProfileData() async {
    final accountRepo = context.read<AccountCubit>().accountRepository;

    try {
      final results = await Future.wait([
        accountRepo.getCustomerProfile().catchError((_) => <String, dynamic>{}),
        accountRepo.getSavingsAccounts().catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final profileRaw = results[0] as Map<String, dynamic>;
      Map<String, dynamic> profile = {};
      if (profileRaw['customer'] is Map<String, dynamic>) {
        profile = profileRaw['customer'] as Map<String, dynamic>;
      } else if (profileRaw['data'] is Map<String, dynamic>) {
        profile = profileRaw['data'] as Map<String, dynamic>;
      } else {
        profile = profileRaw;
      }

      final accountsRaw = results[1] as List<dynamic>;
      List<dynamic> accounts = accountsRaw;

      return {
        'profile': profile,
        'accounts': accounts,
      };
    } catch (_) {
      return {
        'profile': <String, dynamic>{},
        'accounts': <dynamic>[],
      };
    }
  }

  String _maskAccount(String a) {
    if (a.length < 6) return a;
    return '${a.substring(0, 3)} **** ${a.substring(a.length - 3)}';
  }

  String _maskEmail(String e) {
    if (!e.contains('@')) return e;
    final parts = e.split('@');
    final name = parts[0];
    if (name.length <= 2) return e;
    return '${name.substring(0, 2)}****@${parts[1]}';
  }

  String _maskPhone(String p) {
    if (p.length < 8) return p;
    return '${p.substring(0, 4)} **** ${p.substring(p.length - 3)}';
  }

  void _showToast(String message) {
    AppToast.showSuccess(context, message);
  }

  void _showApplicationsSheet(BuildContext context) {
    final repo = context.read<AccountCubit>().accountRepository;
    final future = repo.getUserApplications();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.78,
          ),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Riwayat Pengajuan Produk',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: titleDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Status pengajuan deposito & pinjaman Anda',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    icon: const Icon(Icons.close_rounded, color: textMuted),
                  ),
                ],
              ),
              const Divider(height: 18, color: borderLight),
              Flexible(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: future,
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator(color: primaryNavy)),
                      );
                    }
                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.assignment_outlined, color: textMuted, size: 30),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Belum Ada Riwayat Pengajuan',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: titleDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pengajuan pembukaan deposito atau fasilitas pinjaman yang Anda kirim melalui aplikasi akan tampil di sini.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, index) {
                        final app = items[index];
                        final prodName = (app['product_name'] ?? 'Produk Bank DMB').toString();
                        final prodType = (app['product_type'] ?? '').toString().toUpperCase();
                        final status = (app['status'] ?? 'PENDING').toString().toUpperCase();
                        final amount = Money.tryParse(app['amount']);
                        final tenor = app['tenor_months']?.toString() ?? '-';
                        final createdAt = (app['created_at'] ?? '').toString();
                        final isApproved = status == 'APPROVED' || status == 'DISETUJUI';
                        final isRejected = status == 'REJECTED' || status == 'DITOLAK';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: bgCanvas,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      prodName,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: titleDark,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isApproved
                                          ? AppColors.successLight
                                          : isRejected
                                              ? AppColors.dangerLight
                                              : AppColors.warningLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: isApproved
                                            ? dmbGreen
                                            : isRejected
                                                ? dmbRed
                                                : AppColors.warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$prodType \u2022 Tenor $tenor Bulan',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
                                  ),
                                  Text(
                                    CurrencyFormatter.formatRupiah(amount),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: primaryNavy,
                                    ),
                                  ),
                                ],
                              ),
                              if (createdAt.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Diajukan: ${CurrencyFormatter.formatDateShort(createdAt)}',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: textMuted),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinVerificationModal(BuildContext context, VoidCallback onVerified) {
    final pinController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: borderLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryBorder),
                  ),
                  child: const Icon(Icons.lock_rounded, color: royalBlue, size: 26),
                ),
                const SizedBox(height: 14),
                Text(
                  'Verifikasi Akses Data Pribadi',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: titleDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Masukkan PIN transaksi untuk membuka proteksi data identitas nasabah.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted, height: 1.4),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 10,
                    color: titleDark,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '\u2022\u2022\u2022\u2022\u2022\u2022',
                    hintStyle: const TextStyle(letterSpacing: 10, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: bgCanvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: borderLight, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final pin = pinController.text.trim();
                      if (pin.length != 6) {
                        AppToast.showWarning(context, 'PIN harus 6 digit', title: 'Validasi PIN');
                        return;
                      }
                      try {
                        final revealed = await this.context.read<AccountCubit>().accountRepository.revealCustomerProfile(pin);
                        if (!mounted) return;
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        _revealedProfile = revealed;
                        onVerified();
                        _showToast('Proteksi data pribadi dibuka');
                      } on ApiException catch (e) {
                        if (!mounted) return;
                        AppToast.showError(this.context, ApiException.humanize(e), title: 'Verifikasi PIN');
                      } catch (e) {
                        if (!mounted) return;
                        AppToast.showError(
                          this.context,
                          ApiException.humanize(
                            e,
                            fallback: 'Verifikasi PIN gagal. Silakan coba beberapa saat lagi.',
                          ),
                          title: 'Verifikasi PIN',
                        );
                      }
                    },
                    child: Text(
                      'Buka Proteksi',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: borderLight,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                child: const Icon(Icons.logout_rounded, color: dmbRed, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Keluar dari Aplikasi?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sesi login Anda di DMB Mobile akan diakhiri dengan aman. Anda dapat masuk kembali kapan saja.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted, height: 1.45),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: titleDark,
                        side: const BorderSide(color: borderLight, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => Navigator.of(bottomSheetContext).pop(),
                      child: Text(
                        'Batal',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: dmbRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.of(bottomSheetContext).pop();
                        context.read<AuthCubit>().logout();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      child: Text(
                        'Ya, Keluar',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _versionLabel(DynamicAppConfig config) {
    final shortName = config.bankShortName.isNotEmpty ? config.bankShortName : 'Bank DMB';
    final flavor = AppEnvironment.flavor;
    final envSuffix = (flavor == null || flavor == AppFlavor.production)
        ? ''
        : ' (${flavor.name.toUpperCase()})';
    return '$shortName Mobile v1.0.0$envSuffix';
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final accountCubit = context.watch<AccountCubit>();
    final accountState = accountCubit.state;
    final config = DynamicConfigService().config;

    return AuthSwooshCanvas(
      child: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? {};
          final baseProfile = data['profile'] as Map<String, dynamic>? ?? {};
          final profile = (!_isDataMasked && _revealedProfile != null)
              ? {...baseProfile, ..._revealedProfile!}
              : baseProfile;

          String fullName = profile['name']?.toString() ??
              profile['nama']?.toString() ??
              profile['holder_name']?.toString() ??
              '';
          if (authState is AuthAuthenticated && fullName.isEmpty && authState.user.fullName.isNotEmpty) {
            fullName = authState.user.fullName;
          }

          String rawAccountNo = '';
          if (accountState is AccountLoaded) {
            if (accountState.account.holderName.isNotEmpty && fullName.isEmpty) {
              fullName = accountState.account.holderName;
            }
            if (accountState.account.accountNumber.isNotEmpty) {
              rawAccountNo = accountState.account.accountNumber;
            }
          } else if (authState is AuthAuthenticated && authState.user.primaryAccount.isNotEmpty) {
            rawAccountNo = authState.user.primaryAccount;
          }

          if (fullName.isEmpty) fullName = 'Nasabah Bank DMB';
          final digitsOnly = rawAccountNo.replaceAll(RegExp(r'\D'), '');
          final maskedAcc = digitsOnly.length >= 4
              ? 'No. Rekening \u2022\u2022\u2022\u2022 ${digitsOnly.substring(digitsOnly.length - 4)}'
              : (rawAccountNo.isNotEmpty ? 'No. Rekening $rawAccountNo' : 'Nasabah Bank DMB');

          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Clean Light Header (matching Pusat Bantuan & Notifikasi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  child: Row(
                    children: [
                      if (!widget.isTab) ...[
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AuthUiTokens.inputBorder),
                              ),
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                size: 19,
                                color: AuthUiTokens.deepCobalt,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Akun Saya',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AuthUiTokens.deepCobalt,
                                letterSpacing: -0.35,
                              ),
                            ),
                            Text(
                              'Profil nasabah & pengaturan layanan',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      setState(() {
                        _profileFuture = _fetchProfileData();
                      });
                      await context.read<AccountCubit>().refresh();
                    },
                    color: AuthUiTokens.deepCobalt,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(18, 6, 18, widget.isTab ? 100 : 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                    // Profile Summary Card (clean white + subtle diagonal Bank DMB accent)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE8EEF6)),
                        boxShadow: [
                          BoxShadow(
                            color: AuthUiTokens.deepCobalt.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 155,
                                  child: CustomPaint(
                                    painter: _ProfileCardWavePainter(),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 54,
                                        height: 54,
                                        child: CustomPaint(
                                          painter: _DualToneAvatarPainter(),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fullName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF032B66),
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              maskedAcc,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF334155),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AuthUiTokens.deepCobalt,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),
                    const SizedBox(height: 10),
                    _buildMenuSectionCard([
                      _ProfileMenuEntry(
                        iconType: _ProfileMenuIconType.security,
                        title: 'Pengaturan Keamanan',
                        subtitle: 'Kelola PIN, kata sandi & biometrik',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                        ),
                      ),
                      _ProfileMenuEntry(
                        iconType: _ProfileMenuIconType.helpdesk,
                        title: 'Pusat Bantuan',
                        subtitle: 'Asisten virtual, FAQ & contact center',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                        ),
                      ),
                      _ProfileMenuEntry(
                        iconType: _ProfileMenuIconType.bank,
                        title: 'Tentang Bank DMB',
                        subtitle: 'Profil, visi, misi & legalitas',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CompanyProfileScreen()),
                        ),
                      ),
                      _ProfileMenuEntry(
                        iconType: _ProfileMenuIconType.terms,
                        title: 'Syarat & Ketentuan',
                        subtitle: 'Dokumen ketentuan layanan',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TermsConditionsScreen(readOnly: true)),
                        ),
                      ),
                      _ProfileMenuEntry(
                        iconType: _ProfileMenuIconType.logout,
                        title: 'Keluar dari Akun',
                        subtitle: 'Akhiri sesi Mobile Banking',
                        isDanger: true,
                        onTap: () => _showLogoutDialog(context),
                      ),
                    ]),

                    const SizedBox(height: 20),

                    Center(
                      child: Column(
                        children: [
                          Text(
                            _versionLabel(config),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Berizin & Diawasi oleh Otoritas Jasa Keuangan (OJK)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: textMuted.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
          );
        },
      ),
    );
  }

  Widget _buildMenuSectionCard(List<_ProfileMenuEntry> entries) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: AuthUiTokens.deepCobalt.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: List.generate(entries.length, (i) {
          final item = entries[i];
          final isLast = i == entries.length - 1;
          return Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(18) : Radius.zero,
                  bottom: isLast ? const Radius.circular(18) : Radius.zero,
                ),
                onTap: item.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: item.isDanger
                              ? AppColors.dangerLight
                              : AuthUiTokens.softBlueBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CustomPaint(
                              painter: _ProfileMenuIconPainter(
                                type: item.iconType,
                                strokeColor: item.isDanger ? dmbRed : AuthUiTokens.deepCobalt,
                                fillColor: item.isDanger
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFF7DD3FC),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: item.isDanger ? dmbRed : AuthUiTokens.titleDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AuthUiTokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AuthUiTokens.royalBlue,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.only(left: 72, right: 16),
                  child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                ),
            ],
          );
        }),
      ),
    );
  }
  Widget _buildDataRow({
    required String label,
    required String value,
    bool hasCopy = false,
    String? rawCopyText,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: titleDark,
                  ),
                ),
              ),
              if (hasCopy && rawCopyText != null && rawCopyText != '-' && rawCopyText.isNotEmpty) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: rawCopyText));
                    _showToast('$label disalin');
                  },
                  child: const Icon(Icons.copy_rounded, size: 13, color: royalBlue),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMenuCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: AuthUiTokens.deepCobalt.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 21),
      ),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: titleDark,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          color: textMuted,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
    );
  }

  String _formatAccountNo(String acc) {
    if (acc.length == 16) {
      return '${acc.substring(0, 4)} ${acc.substring(4, 8)} ${acc.substring(8, 12)} ${acc.substring(12)}';
    }
    return acc;
  }
}

enum _ProfileMenuIconType { security, helpdesk, bank, terms, logout }

class _ProfileMenuEntry {
  final _ProfileMenuIconType iconType;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDanger;

  const _ProfileMenuEntry({
    required this.iconType,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDanger = false,
  });
}

class _ProfileMenuIconPainter extends CustomPainter {
  const _ProfileMenuIconPainter({
    required this.type,
    required this.strokeColor,
    required this.fillColor,
  });

  final _ProfileMenuIconType type;
  final Color strokeColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()
      ..color = fillColor.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case _ProfileMenuIconType.security:
        // Shield with check duotone
        final shield = Path()
          ..moveTo(w * 0.50, h * 0.12)
          ..lineTo(w * 0.82, h * 0.24)
          ..lineTo(w * 0.82, h * 0.50)
          ..quadraticBezierTo(w * 0.82, h * 0.76, w * 0.50, h * 0.88)
          ..quadraticBezierTo(w * 0.18, h * 0.76, w * 0.18, h * 0.50)
          ..lineTo(w * 0.18, h * 0.24)
          ..close();
        canvas.drawPath(shield, fill);
        canvas.drawPath(shield, stroke);
        canvas.drawLine(Offset(w * 0.36, h * 0.50), Offset(w * 0.46, h * 0.60), stroke);
        canvas.drawLine(Offset(w * 0.46, h * 0.60), Offset(w * 0.65, h * 0.40), stroke);
        break;

      case _ProfileMenuIconType.helpdesk:
        // Headset duotone
        final band = Path()
          ..moveTo(w * 0.20, h * 0.56)
          ..quadraticBezierTo(w * 0.20, h * 0.18, w * 0.50, h * 0.18)
          ..quadraticBezierTo(w * 0.80, h * 0.18, w * 0.80, h * 0.56);
        canvas.drawPath(band, stroke);
        final leftEar = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.14, h * 0.48, w * 0.16, h * 0.28),
          const Radius.circular(4),
        );
        final rightEar = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.70, h * 0.48, w * 0.16, h * 0.28),
          const Radius.circular(4),
        );
        canvas.drawRRect(leftEar, fill);
        canvas.drawRRect(rightEar, fill);
        canvas.drawRRect(leftEar, stroke);
        canvas.drawRRect(rightEar, stroke);
        final mic = Path()
          ..moveTo(w * 0.78, h * 0.76)
          ..quadraticBezierTo(w * 0.78, h * 0.86, w * 0.56, h * 0.86);
        canvas.drawPath(mic, stroke);
        break;

      case _ProfileMenuIconType.bank:
        // Bank building duotone
        final roof = Path()
          ..moveTo(w * 0.12, h * 0.38)
          ..lineTo(w * 0.50, h * 0.14)
          ..lineTo(w * 0.88, h * 0.38)
          ..close();
        canvas.drawPath(roof, fill);
        canvas.drawPath(roof, stroke);
        canvas.drawRect(Rect.fromLTWH(w * 0.22, h * 0.44, w * 0.56, h * 0.34), fill);
        canvas.drawLine(Offset(w * 0.26, h * 0.42), Offset(w * 0.26, h * 0.78), stroke);
        canvas.drawLine(Offset(w * 0.50, h * 0.42), Offset(w * 0.50, h * 0.78), stroke);
        canvas.drawLine(Offset(w * 0.74, h * 0.42), Offset(w * 0.74, h * 0.78), stroke);
        canvas.drawLine(Offset(w * 0.14, h * 0.84), Offset(w * 0.86, h * 0.84), stroke);
        break;

      case _ProfileMenuIconType.terms:
        // Document sheet duotone
        final doc = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.20, h * 0.12, w * 0.60, h * 0.76),
          const Radius.circular(3.5),
        );
        canvas.drawRRect(doc, fill);
        canvas.drawRRect(doc, stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.36), Offset(w * 0.66, h * 0.36), stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.52), Offset(w * 0.66, h * 0.52), stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.68), Offset(w * 0.52, h * 0.68), stroke);
        break;

      case _ProfileMenuIconType.logout:
        // Door + exit arrow duotone
        final door = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.16, h * 0.16, w * 0.38, h * 0.68),
          const Radius.circular(3.5),
        );
        canvas.drawRRect(door, fill);
        canvas.drawRRect(door, stroke);
        canvas.drawLine(Offset(w * 0.44, h * 0.50), Offset(w * 0.86, h * 0.50), stroke);
        canvas.drawLine(Offset(w * 0.70, h * 0.35), Offset(w * 0.86, h * 0.50), stroke);
        canvas.drawLine(Offset(w * 0.70, h * 0.65), Offset(w * 0.86, h * 0.50), stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ProfileMenuIconPainter oldDelegate) =>
      oldDelegate.type != type;
}

class _DualToneAvatarPainter extends CustomPainter {
  const _DualToneAvatarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(16),
    );
    canvas.drawRRect(bgRect, Paint()..color = const Color(0xFFEFF6FF));
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = const Color(0xFFD6E6FA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final fill = Paint()
      ..color = const Color(0xFF7DD3FC).withValues(alpha: 0.78)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = const Color(0xFF033172)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Head
    canvas.drawCircle(Offset(w * 0.50, h * 0.36), w * 0.14, fill);
    canvas.drawCircle(Offset(w * 0.50, h * 0.36), w * 0.14, stroke);

    // Shoulders
    final body = Path()
      ..moveTo(w * 0.24, h * 0.76)
      ..quadraticBezierTo(w * 0.24, h * 0.54, w * 0.50, h * 0.54)
      ..quadraticBezierTo(w * 0.76, h * 0.54, w * 0.76, h * 0.76)
      ..close();
    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProfileCardWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final p1 = Paint()
      ..color = const Color(0xFF0550A6).withValues(alpha: 0.08);
    final path1 = Path()
      ..moveTo(w * 0.35, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.15, h)
      ..close();
    canvas.drawPath(path1, p1);

    final p2 = Paint()
      ..color = const Color(0xFF033172).withValues(alpha: 0.06);
    final path2 = Path()
      ..moveTo(w * 0.62, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.42, h)
      ..close();
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
