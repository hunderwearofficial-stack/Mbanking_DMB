import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/user_model.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';

class AccountInfoScreen extends StatefulWidget {
  final bool isTab;
  const AccountInfoScreen({super.key, this.isTab = false});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _baseProfile = {};
  List<dynamic> _accountsList = [];
  bool _isDataMasked = true;
  Map<String, dynamic>? _revealedProfile;

  String _maskCIF(String c) {
    if (c.length < 8) return c;
    return '${c.substring(0, 4)} **** ${c.substring(c.length - 4)}';
  }

  String _maskPhone(String p) {
    if (p.length < 8) return p;
    return '${p.substring(0, 4)} **** ${p.substring(p.length - 3)}';
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
                        AppToast.showSuccess(this.context, 'Proteksi data pribadi dibuka');
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

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final accountRepo = context.read<AccountCubit>().accountRepository;

    try {
      final results = await Future.wait([
        accountRepo.getCustomerProfile(),
        accountRepo.getSavingsAccounts(),
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

      if (!mounted) return;
      setState(() {
        _baseProfile = profile;
        _accountsList = accountsRaw;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ApiException.humanize(
          e,
          fallback: 'Data informasi rekening belum dapat dimuat. Silakan coba kembali.',
        );
        _isLoading = false;
      });
    }
  }

  void _showToast(String message) {
    AppToast.showSuccess(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final accountState = context.watch<AccountCubit>().state;

    UserModel? authUser;
    if (authState is AuthAuthenticated) {
      authUser = authState.user;
    }

    AccountModel? activeAccount;
    if (accountState is AccountLoaded) {
      activeAccount = accountState.account;
    }

    final profile = (!_isDataMasked && _revealedProfile != null)
        ? {..._baseProfile, ..._revealedProfile!}
        : _baseProfile;

    String cif = (profile['cif'] ?? profile['cif_number'] ?? authUser?.cif ?? '').toString().trim();
    if (cif.isEmpty || cif == 'null') {
      cif = '-';
    }

    String nama = (profile['nama'] ?? profile['full_name'] ?? authUser?.fullName ?? activeAccount?.holderName ?? '').toString().trim();
    if (nama.isEmpty || nama == 'null') {
      nama = '-';
    }

    String nohp = (profile['nohp'] ?? profile['phone_number'] ?? authUser?.phoneNumber ?? '').toString().trim();
    if (nohp.isEmpty || nohp == 'null') {
      nohp = '-';
    }

    String tempatLahir = (profile['tempat_lahir'] ?? authUser?.tempatLahir ?? '').toString().trim();
    String tglLahir = (profile['tgl_lahir'] ?? authUser?.tglLahir ?? '').toString().trim();
    if (tglLahir.contains('T')) {
      tglLahir = tglLahir.split('T').first;
    }

    List<Map<String, dynamic>> parsedAccounts = [];
    for (final item in _accountsList) {
      if (item is Map) {
        final noRek = (item['nomor_rekening'] ?? item['no_rek'] ?? '').toString();
        final prod = (item['nama_produk'] ??
                item['produk_tabungan'] ??
                item['jenis'] ??
                item['kode_produk'] ??
                'Tabungan Bank DMB')
            .toString()
            .trim();
        final saldo = Money.tryParse(item['saldo'] ?? item['saldo_akhir']);
        if (noRek.isNotEmpty && noRek != '-') {
          parsedAccounts.add({
            'no_rek': noRek,
            'jenis': prod.isEmpty || prod == 'null' ? 'Tabungan Bank DMB' : prod,
            'saldo': saldo,
          });
        }
      }
    }

    if (parsedAccounts.isEmpty && activeAccount != null && activeAccount.accountNumber.isNotEmpty) {
      parsedAccounts.add({
        'no_rek': activeAccount.accountNumber,
        'jenis': activeAccount.accountType.isNotEmpty
            ? activeAccount.accountType
            : 'Tabungan Bank DMB',
        'saldo': activeAccount.balance,
      });
    }

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
          'Informasi Rekening',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0A2A66),
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 0.5,
              shadowColor: Colors.black.withOpacity(0.08),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _loadProfileData,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF0A2A66)),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryNavy),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await _loadProfileData();
                if (context.mounted) {
                  await context.read<AccountCubit>().refresh();
                }
              },
              color: primaryNavy,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 18),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.warningBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_rounded, color: AppColors.warning, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: titleDark,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _loadProfileData,
                              style: TextButton.styleFrom(
                                foregroundColor: primaryNavy,
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                'Coba Lagi',
                                style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nomor CIF Nasabah',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _isDataMasked ? _maskCIF(cif) : cif,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          if (cif != '-' && cif.isNotEmpty)
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: cif));
                                _showToast('Nomor CIF disalin: $cif');
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.20),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.copy_rounded, color: Colors.white, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Salin CIF',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                            const Icon(Icons.lock_outline_rounded, size: 16, color: royalBlue),
                            const SizedBox(width: 6),
                            Text(
                              'Data Identitas Nasabah',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14.5,
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
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _isDataMasked ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  size: 15,
                                  color: royalBlue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isDataMasked ? 'Buka Proteksi' : 'Kunci Data',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
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
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
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
                      child: Column(
                        children: [
                          _buildDetailRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Nama Lengkap',
                            value: nama,
                          ),
                          const Divider(height: 18, color: Color(0xFFF1F5F9)),
                          _buildDetailRow(
                            icon: Icons.phone_android_rounded,
                            label: 'Nomor Handphone',
                            value: _isDataMasked ? _maskPhone(nohp) : nohp,
                          ),
                          if (tempatLahir.isNotEmpty && tglLahir.isNotEmpty) ...[
                            const Divider(height: 18, color: Color(0xFFF1F5F9)),
                            _buildDetailRow(
                              icon: Icons.cake_outlined,
                              label: 'Tempat, Tgl Lahir',
                              value: _isDataMasked ? '$tempatLahir, **-**-****' : '$tempatLahir, $tglLahir',
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Portofolio Rekening Tabungan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${parsedAccounts.length} Rekening',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: royalBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (parsedAccounts.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderLight),
                        ),
                        child: Center(
                          child: Text(
                            'Belum ada data rekening tabungan yang dapat ditampilkan.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                          ),
                        ),
                      )
                    else
                      ...parsedAccounts.map((map) {
                        final noRek = map['no_rek']?.toString() ?? '-';
                        final canCopyRek = noRek.isNotEmpty && noRek != '-';
                        final saldo = map['saldo'] is Money ? map['saldo'] as Money : null;
                        final type = map['jenis']?.toString() ?? 'Tabungan Bank DMB';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(18),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.account_balance_wallet_outlined,
                                            color: Color(0xFF0A2A66),
                                            size: 19,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            type,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF0A2A66),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE6F7F1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'AKTIF',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F9D76),
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
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'No. Rekening',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      InkWell(
                                        onTap: canCopyRek
                                            ? () {
                                                Clipboard.setData(ClipboardData(text: noRek));
                                                _showToast('Nomor rekening disalin: $noRek');
                                              }
                                            : null,
                                        child: Row(
                                          children: [
                                            Text(
                                              noRek,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF0A2A66),
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                            if (canCopyRek) ...[
                                              const SizedBox(width: 6),
                                              const Icon(Icons.copy_rounded, color: Color(0xFF0D3882), size: 14),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Saldo Tersedia',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        CurrencyFormatter.formatRupiah(saldo),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: const Color(0xFF0A2A66),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_rounded, color: royalBlue, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Data profil nasabah terverifikasi resmi oleh ${DynamicConfigService().config.bankName}.',
                              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool copyable = false,
    VoidCallback? onCopy,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: textMuted),
        const SizedBox(width: 10),
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
              if (copyable) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onCopy,
                  child: const Icon(Icons.copy_rounded, size: 14, color: royalBlue),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
