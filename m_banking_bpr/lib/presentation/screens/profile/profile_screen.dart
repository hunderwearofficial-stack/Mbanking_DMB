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
import '../account/account_info_screen.dart';
import '../auth/login_screen.dart';
import '../auth/terms_conditions_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../mutation/mutation_screen.dart';
import '../statement/estatement_screen.dart';
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
                                    '$prodType • Tenor $tenor Bulan',
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
                    hintText: '••••••',
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F6F2),
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF0A2A66),
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: widget.isTab ? 18 : 8,
        leadingWidth: widget.isTab ? 0 : 64,
        leading: widget.isTab
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 0.5,
                  shadowColor: Colors.black.withOpacity(0.08),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Center(
                      child: Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF0A2A66)),
                    ),
                  ),
                ),
              ),
        title: Text(
          'Akun Saya',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0A2A66),
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? {};
          final baseProfile = data['profile'] as Map<String, dynamic>? ?? {};
          final profile = (!_isDataMasked && _revealedProfile != null) ? {...baseProfile, ..._revealedProfile!} : baseProfile;

          String fullName = profile['name']?.toString() ??
              profile['nama']?.toString() ??
              profile['holder_name']?.toString() ??
              '';
          String username = profile['username']?.toString() ?? '';
          String phone = profile['phone']?.toString() ??
              profile['phone_number']?.toString() ??
              '';
          String email = profile['email']?.toString() ?? '';

          if (authState is AuthAuthenticated) {
            if (fullName.isEmpty && authState.user.fullName.isNotEmpty) {
              fullName = authState.user.fullName;
            }
            if (username.isEmpty && authState.user.username.isNotEmpty) {
              username = authState.user.username;
            }
            if (phone.isEmpty) phone = authState.user.phoneNumber;
            if (email.isEmpty && authState.user.email.isNotEmpty) {
              email = authState.user.email;
            }
          }

          String primaryAccountNo = '-';
          String rawAccountNo = '-';
          String accountType = 'Tabungan Bank DMB';
          Money? balance;
          bool isBalanceVisible = accountCubit.isBalanceVisible;

          if (accountState is AccountLoaded) {
            isBalanceVisible = accountState.isBalanceVisible;
            if (accountState.account.holderName.isNotEmpty && fullName.isEmpty) {
              fullName = accountState.account.holderName;
            }
            if (accountState.account.accountNumber.isNotEmpty) {
              rawAccountNo = accountState.account.accountNumber;
              primaryAccountNo = _formatAccountNo(rawAccountNo);
            }
            if (accountState.account.accountType.trim().isNotEmpty &&
                accountState.account.accountType.trim() != '-') {
              accountType = accountState.account.accountType.trim();
            }
            balance = accountState.account.balance;
          }

          if (fullName.isEmpty) fullName = 'Nasabah Bank DMB';
          final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'N';
          final canCopyAccount = rawAccountNo.isNotEmpty && rawAccountNo != '-';

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _profileFuture = _fetchProfileData();
              });
              await context.read<AccountCubit>().refresh();
            },
            color: primaryNavy,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(18, 12, 18, widget.isTab ? 110 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0A2A66),
                          Color(0xFF0D3882),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0A2A66).withOpacity(0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: primaryNavy,
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
                                fullName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                phone.isNotEmpty
                                    ? _maskPhone(phone)
                                    : 'Nasabah Resmi ${config.bankShortName}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.88),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'NASABAH TERVERIFIKASI',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'Informasi Rekening Tabungan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderLight),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rekening Utama',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  primaryAccountNo,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: primaryNavy,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            if (canCopyAccount)
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: rawAccountNo));
                                  _showToast('Nomor rekening disalin: $rawAccountNo');
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.primaryBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.copy_rounded, color: royalBlue, size: 13),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Salin',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: royalBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Saldo Rekening',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isBalanceVisible
                                      ? CurrencyFormatter.formatRupiah(balance)
                                      : 'Rp •••••••••',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: titleDark,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                isBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20,
                                color: textMuted,
                              ),
                              onPressed: () {
                                context.read<AccountCubit>().toggleBalanceVisibility();
                                setState(() {});
                              },
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Jenis Tabungan',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    accountType,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: titleDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.successBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: dmbGreen, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'AKUN AKTIF',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: dmbGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isDataMasked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                            size: 16,
                            color: _isDataMasked ? royalBlue : dmbGreen,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Data Identitas (Terproteksi)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: titleDark,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () {
                          if (_isDataMasked) {
                            _showPinVerificationModal(context, () {
                              setState(() => _isDataMasked = false);
                            });
                          } else {
                            setState(() {
                              _isDataMasked = true;
                              _revealedProfile = null;
                            });
                            _showToast('Data identitas kembali diproteksi');
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isDataMasked ? AppColors.primaryLight : AppColors.successLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isDataMasked ? AppColors.primaryBorder : AppColors.successBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isDataMasked ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 13,
                                color: _isDataMasked ? royalBlue : dmbGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isDataMasked ? 'Buka Data' : 'Kunci Data',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _isDataMasked ? royalBlue : dmbGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderLight),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildDataRow(
                          label: 'Nomor Rekening Utama',
                          value: _isDataMasked ? _maskAccount(rawAccountNo) : primaryAccountNo,
                          hasCopy: canCopyAccount,
                          rawCopyText: rawAccountNo,
                        ),
                        if (username.isNotEmpty) ...[
                          const Divider(height: 16, color: Color(0xFFF1F5F9)),
                          _buildDataRow(
                            label: 'Username / ID Pengguna',
                            value: username,
                            hasCopy: true,
                            rawCopyText: username,
                          ),
                        ],
                        const Divider(height: 16, color: Color(0xFFF1F5F9)),
                        _buildDataRow(
                          label: 'Nomor Handphone Terdaftar',
                          value: _isDataMasked ? _maskPhone(phone) : phone,
                        ),
                        if (email.isNotEmpty) ...[
                          const Divider(height: 16, color: Color(0xFFF1F5F9)),
                          _buildDataRow(
                            label: 'Email Terdaftar',
                            value: _isDataMasked ? _maskEmail(email) : email,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'Portofolio & Aktivitas',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMenuCard(
                    children: [
                      _buildMenuItem(
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: royalBlue,
                        iconBg: AppColors.primaryLight,
                        title: 'Informasi Rekening & CIF',
                        subtitle: 'Detail rekening tabungan & identitas CIF',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                      _buildMenuItem(
                        icon: Icons.history_rounded,
                        iconColor: dmbGreen,
                        iconBg: AppColors.successLight,
                        title: 'Riwayat Transaksi',
                        subtitle: 'Catatan mutasi uang masuk & keluar',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const MutationScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                      _buildMenuItem(
                        icon: Icons.analytics_outlined,
                        iconColor: primaryNavy,
                        iconBg: const Color(0xFFF1F5F9),
                        title: 'e-Statement Rekening',
                        subtitle: 'Ringkasan mutasi bulanan 6 bulan terakhir',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const EStatementScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                      _buildMenuItem(
                        icon: Icons.assignment_turned_in_outlined,
                        iconColor: AppColors.warning,
                        iconBg: AppColors.warningLight,
                        title: 'Riwayat Pengajuan Produk',
                        subtitle: 'Pantau status pengajuan deposito & pinjaman',
                        onTap: () => _showApplicationsSheet(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'Pengaturan Aplikasi',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMenuCard(
                    children: [
                      _buildMenuItem(
                        icon: Icons.settings_outlined,
                        iconColor: royalBlue,
                        iconBg: AppColors.primaryLight,
                        title: 'Pengaturan & Keamanan Akun',
                        subtitle: 'Ganti kata sandi, PIN transaksi & perangkat',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'Layanan & Bantuan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMenuCard(
                    children: [
                      _buildMenuItem(
                        icon: Icons.apartment_rounded,
                        iconColor: royalBlue,
                        iconBg: AppColors.primaryLight,
                        title: 'Tentang ${config.bankShortName}',
                        subtitle: 'Profil perusahaan, visi misi & legalitas OJK/LPS',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CompanyProfileScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                      _buildMenuItem(
                        icon: Icons.headset_mic_outlined,
                        iconColor: royalBlue,
                        iconBg: AppColors.primaryLight,
                        title: 'Pusat Bantuan 24 Jam',
                        subtitle: 'Call Center, WhatsApp & Email resmi',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
                      _buildMenuItem(
                        icon: Icons.policy_outlined,
                        iconColor: dmbGreen,
                        iconBg: AppColors.successLight,
                        title: 'Syarat & Ketentuan',
                        subtitle: 'Kebijakan privasi & aturan perbankan',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TermsConditionsScreen(readOnly: true),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 26),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dmbRed,
                        side: const BorderSide(color: AppColors.dangerBorder, width: 1.5),
                        backgroundColor: AppColors.dangerLight,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _showLogoutDialog(context),
                      icon: const Icon(Icons.logout_rounded, size: 19),
                      label: Text(
                        'Keluar dari Aplikasi',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

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
          );
        },
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
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
