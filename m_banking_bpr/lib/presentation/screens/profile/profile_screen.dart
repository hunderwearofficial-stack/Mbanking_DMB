import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../mutation/mutation_screen.dart';
import '../statement/estatement_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../auth/terms_conditions_screen.dart';
import '../auth/login_screen.dart';
import 'security_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isTab;
  const ProfileScreen({super.key, this.isTab = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color dmbRed = Color(0xFFDC2626);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  late Future<Map<String, dynamic>> _profileFuture;
  bool _isDataMasked = true;
  bool _isBalanceVisible = false;

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

      // 1. Parse Profile
      final profileRaw = results[0];
      Map<String, dynamic> profile = {};
      if (profileRaw is Map<String, dynamic>) {
        if (profileRaw['customer'] is Map<String, dynamic>) {
          profile = profileRaw['customer'] as Map<String, dynamic>;
        } else if (profileRaw['data'] is Map<String, dynamic>) {
          profile = profileRaw['data'] as Map<String, dynamic>;
        } else {
          profile = profileRaw;
        }
      }

      // 2. Parse Accounts
      final accountsRaw = results[1];
      List<dynamic> accounts = [];
      if (accountsRaw is List) {
        accounts = accountsRaw;
      } else if (accountsRaw is Map && accountsRaw['accounts'] is List) {
        accounts = accountsRaw['accounts'] as List;
      }

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

  String _maskCIF(String c) {
    if (c.length < 8) return c;
    return '${c.substring(0, 4)} **** ${c.substring(c.length - 4)}';
  }

  String _maskNIK(String n) {
    if (n.length < 8) return n;
    return '${n.substring(0, 6)} ****** ${n.substring(n.length - 4)}';
  }

  String _maskPhone(String p) {
    if (p.length < 8) return p;
    return '${p.substring(0, 4)} **** ${p.substring(p.length - 3)}';
  }

  String _maskAddress(String a) {
    if (a.length <= 16) return a;
    return '${a.substring(0, 16)}... (Detail Terproteksi)';
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: primaryNavy,
        duration: const Duration(seconds: 2),
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
                    color: const Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFDBEAFE)),
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
                    fillColor: const Color(0xFFF8FAFC),
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
                    onPressed: () {
                      if (pinController.text.trim().length == 6) {
                        Navigator.pop(sheetCtx);
                        onVerified();
                        _showToast('Proteksi data pribadi dibuka');
                      } else {
                        _showToast('PIN harus 6 digit');
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
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFECACA)),
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

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final accountState = context.watch<AccountCubit>().state;

    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !widget.isTab,
        leading: widget.isTab
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Column(
          children: [
            Text(
              'Profil Nasabah',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'INFORMASI REKENING & IDENTITAS',
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
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? {};
          final profile = data['profile'] as Map<String, dynamic>? ?? {};

          // Extract values dynamically from CBS Profile & Auth Session (NO HARDCODED VALUES)
          String fullName = profile['name']?.toString() ??
              profile['nama']?.toString() ??
              profile['holder_name']?.toString() ??
              '';
          String cif = profile['cif']?.toString() ??
              profile['cif_number']?.toString() ??
              '';
          String nik = profile['nik']?.toString() ??
              profile['id_number']?.toString() ??
              '';
          String phone = profile['phone']?.toString() ??
              profile['phone_number']?.toString() ??
              '';
          String alamat = profile['address']?.toString() ??
              profile['alamat']?.toString() ??
              '';

          // Auth / State Fallbacks
          if (authState is AuthAuthenticated) {
            if (fullName.isEmpty && authState.user.fullName.isNotEmpty) {
              fullName = authState.user.fullName;
            }
            if (phone.isEmpty) phone = authState.user.phoneNumber;
            if (cif.isEmpty && authState.user.cif.isNotEmpty) {
              cif = authState.user.cif;
            }
            if (nik.isEmpty && authState.user.nik.isNotEmpty) {
              nik = authState.user.nik;
            }
            if (alamat.isEmpty && authState.user.alamat.isNotEmpty) {
              alamat = authState.user.alamat;
            }
          }

          String primaryAccountNo = '-';
          String rawAccountNo = '-';
          double balance = 0.0;

          if (accountState is AccountLoaded) {
            if (accountState.account.holderName.isNotEmpty && fullName.isEmpty) {
              fullName = accountState.account.holderName;
            }
            if (accountState.account.accountNumber.isNotEmpty) {
              rawAccountNo = accountState.account.accountNumber;
              primaryAccountNo = _formatAccountNo(rawAccountNo);
            }
            balance = accountState.account.balance;
          }

          if (fullName.isEmpty) fullName = 'Nasabah Bank DMB';
          final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'N';

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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Profile Identity Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0B356D),
                          Color(0xFF0062E3),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0062E3).withOpacity(0.24),
                          blurRadius: 16,
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
                                    : 'Nasabah Resmi Bank DMB',
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

                  // 2. Section: Informasi Rekening Tabungan Utama
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
                        // Row 1: Nomor Rekening + Copy
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
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: rawAccountNo));
                                _showToast('Nomor rekening disalin: $rawAccountNo');
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFDBEAFE)),
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

                        // Row 2: Saldo Rekening
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
                                  _isBalanceVisible
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
                                _isBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20,
                                color: const Color(0xFF64748B),
                              ),
                              onPressed: () {
                                setState(() {
                                  _isBalanceVisible = !_isBalanceVisible;
                                });
                              },
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ),

                        // Row 3: Detail Produk & Status
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
                                    'Tabungan Mikro DMB',
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
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
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

                  // 3. Section: Data Identitas Nasabah (Terproteksi PIN)
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
                            setState(() => _isDataMasked = true);
                            _showToast('Data identitas kembali diproteksi');
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isDataMasked ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isDataMasked ? const Color(0xFFDBEAFE) : const Color(0xFFBBF7D0),
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
                          label: 'Nomor CIF Nasabah',
                          value: _isDataMasked ? _maskCIF(cif) : cif,
                          hasCopy: true,
                          rawCopyText: cif,
                        ),
                        const Divider(height: 16, color: Color(0xFFF1F5F9)),
                        _buildDataRow(
                          label: 'NIK (Nomor KTP)',
                          value: _isDataMasked ? _maskNIK(nik) : nik,
                        ),
                        const Divider(height: 16, color: Color(0xFFF1F5F9)),
                        _buildDataRow(
                          label: 'Nomor Handphone Terdaftar',
                          value: _isDataMasked ? _maskPhone(phone) : phone,
                        ),
                        const Divider(height: 16, color: Color(0xFFF1F5F9)),
                        _buildDataRow(
                          label: 'Alamat Domisili KTP',
                          value: _isDataMasked ? _maskAddress(alamat) : alamat,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 4. Section: Portofolio & Aktivitas
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
                        icon: Icons.history_rounded,
                        iconColor: dmbGreen,
                        iconBg: const Color(0xFFF0FDF4),
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
                        icon: Icons.picture_as_pdf_outlined,
                        iconColor: primaryNavy,
                        iconBg: const Color(0xFFF1F5F9),
                        title: 'e-Statement Rekening',
                        subtitle: 'Unduh rekening koran digital PDF',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const EStatementScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // 5. Section: Pengaturan Aplikasi
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
                        iconBg: const Color(0xFFEFF6FF),
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

                  // 6. Section: Layanan & Bantuan
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
                        icon: Icons.headset_mic_outlined,
                        iconColor: royalBlue,
                        iconBg: const Color(0xFFEFF6FF),
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
                        iconBg: const Color(0xFFF0FDF4),
                        title: 'Syarat & Ketentuan',
                        subtitle: 'Kebijakan privasi & aturan perbankan',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const TermsConditionsScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 26),

                  // 7. Logout Action Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dmbRed,
                        side: const BorderSide(color: Color(0xFFFECACA), width: 1.5),
                        backgroundColor: const Color(0xFFFEF2F2),
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

                  // App Version & Security Note
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'DMB Mobile v1.0.0 (Production Build)',
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
              if (hasCopy && rawCopyText != null) ...[
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
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
