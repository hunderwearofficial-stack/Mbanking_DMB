import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  Map<String, dynamic> _bankConfig = {};
  List<Map<String, dynamic>> _myApplications = [];
  String _deviceId = '-';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final accountRepo = context.read<AccountCubit>().accountRepository;
      final authRepo = context.read<AuthCubit>().authRepository;
      final devId = await authRepo.secureStorage.getDeviceID();
      final results = await Future.wait([
        accountRepo.getAppConfig(),
        accountRepo.getUserApplications(),
      ]);
      if (mounted) {
        setState(() {
          _deviceId = devId;
          _bankConfig = results[0] as Map<String, dynamic>;
          _myApplications = results[1] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showChangePasswordModal() {
    final oldPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCCFBF1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF0F766E), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ganti Password Login',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                                ),
                                Text(
                                  'Gunakan minimal 8 karakter kombinasi huruf & angka',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('Password Saat Ini', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: oldPwController,
                        obscureText: obscureOld,
                        decoration: InputDecoration(
                          hintText: 'Masukkan password lama',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(obscureOld ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setSheetState(() => obscureOld = !obscureOld),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Password Baru (Min. 8 Karakter)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: newPwController,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          hintText: 'Masukkan password baru',
                          prefixIcon: const Icon(Icons.vpn_key_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setSheetState(() => obscureNew = !obscureNew),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Konfirmasi Password Baru', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: confirmPwController,
                        obscureText: obscureNew,
                        decoration: const InputDecoration(
                          hintText: 'Ketik ulang password baru',
                          prefixIcon: Icon(Icons.verified_user_outlined, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: submitting
                              ? null
                              : () async {
                                  final oldPw = oldPwController.text.trim();
                                  final newPw = newPwController.text.trim();
                                  final confPw = confirmPwController.text.trim();
                                  if (oldPw.isEmpty || newPw.length < 8) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Password baru minimal harus 8 karakter'),
                                        backgroundColor: AppColors.danger,
                                      ),
                                    );
                                    return;
                                  }
                                  if (newPw != confPw) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Konfirmasi password baru tidak cocok'),
                                        backgroundColor: AppColors.danger,
                                      ),
                                    );
                                    return;
                                  }
                                  setSheetState(() => submitting = true);
                                  try {
                                    await context.read<AuthCubit>().authRepository.changePassword(
                                          oldPassword: oldPw,
                                          newPassword: newPw,
                                        );
                                    if (!mounted) return;
                                    Navigator.pop(sheetCtx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Password login berhasil diperbarui!'),
                                        backgroundColor: AppColors.primary,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  } on ApiException catch (e) {
                                    setSheetState(() => submitting = false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
                                    );
                                  } catch (e) {
                                    setSheetState(() => submitting = false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Gagal: $e'), backgroundColor: AppColors.danger),
                                    );
                                  }
                                },
                          child: submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text('Simpan Password Baru', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showChangePinModal() {
    final oldPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEDD5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.dialpad_rounded, color: Color(0xFFEA580C), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ganti PIN Transaksi 6 Digit',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                                ),
                                Text(
                                  'Digunakan untuk otorisasi setiap transfer dana',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('PIN Transaksi Saat Ini (6 Digit)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: oldPinController,
                        obscureText: true,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: '••••••',
                          prefixIcon: Icon(Icons.lock_clock_outlined, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('PIN Transaksi Baru (6 Digit Angka)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: newPinController,
                        obscureText: true,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: '••••••',
                          prefixIcon: Icon(Icons.pin_outlined, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Konfirmasi PIN Baru', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: confirmPinController,
                        obscureText: true,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: '••••••',
                          prefixIcon: Icon(Icons.check_circle_outline_rounded, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: submitting
                              ? null
                              : () async {
                                  final oldPin = oldPinController.text.trim();
                                  final newPin = newPinController.text.trim();
                                  final confPin = confirmPinController.text.trim();
                                  if (oldPin.length != 6 || newPin.length != 6) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('PIN harus tepat 6 digit angka'),
                                        backgroundColor: AppColors.danger,
                                      ),
                                    );
                                    return;
                                  }
                                  if (newPin != confPin) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Konfirmasi PIN baru tidak cocok'),
                                        backgroundColor: AppColors.danger,
                                      ),
                                    );
                                    return;
                                  }
                                  setSheetState(() => submitting = true);
                                  try {
                                    await context.read<AuthCubit>().authRepository.changePin(
                                          oldPin: oldPin,
                                          newPin: newPin,
                                        );
                                    if (!mounted) return;
                                    Navigator.pop(sheetCtx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('PIN Transaksi 6 Digit berhasil diperbarui!'),
                                        backgroundColor: AppColors.primary,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  } on ApiException catch (e) {
                                    setSheetState(() => submitting = false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
                                    );
                                  } catch (e) {
                                    setSheetState(() => submitting = false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Gagal: $e'), backgroundColor: AppColors.danger),
                                    );
                                  }
                                },
                          child: submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text('Simpan PIN Transaksi Baru', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    String fullName = 'Nasabah Bank DMB';
    String cif = '-';
    String phone = '-';
    String primaryAcc = '-';
    if (authState is AuthAuthenticated) {
      fullName = authState.user.fullName;
      cif = authState.user.cif;
      phone = authState.user.phoneNumber;
      primaryAcc = authState.user.primaryAccount;
    }

    final dailyLimit = (_bankConfig['daily_transfer_limit'] is num)
        ? (_bankConfig['daily_transfer_limit'] as num).toDouble()
        : 25000000.0;
    final minTransfer = (_bankConfig['min_transfer_amount'] is num)
        ? (_bankConfig['min_transfer_amount'] as num).toDouble()
        : 10000.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          'Profil & Keamanan wondr DMB',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Wondr Luxury Profile Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00382E), Color(0xFF00695C), Color(0xFF00897B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF004D40).withOpacity(0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              fullName.isNotEmpty ? fullName[0].toUpperCase() : 'N',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
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
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'CIF: $cif  •  Rek: $primaryAcc',
                                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'No. HP Terdaftar: $phone',
                                style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.75)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.smartphone_rounded, color: Color(0xFF6EE7B7), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Perangkat Terikat: $_deviceId',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'AKTIF',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 2. Pengaturan Keamanan (Self-Service)
              const Text(
                'Pengaturan Keamanan Akun',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    ListTile(
                      onTap: _showChangePasswordModal,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF0F766E)),
                      ),
                      title: const Text('Ganti Password Login', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      subtitle: const Text('Perbarui kata sandi masuk aplikasi Mobile DMB', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                    ),
                    const Divider(height: 1, indent: 18, endIndent: 18),
                    ListTile(
                      onTap: _showChangePinModal,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDD5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.dialpad_rounded, color: Color(0xFFEA580C)),
                      ),
                      title: const Text('Ganti PIN Transaksi 6 Digit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      subtitle: const Text('Ubah PIN otorisasi transfer & pembayaran', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 3. Kebijakan Limit Transaksi Harian (Real-time dari Web Admin)
              const Text(
                'Batas Limit Transaksi Harian Anda',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Limit Transfer Harian', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Text(
                          CurrencyFormatter.formatRupiah(dailyLimit),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Minimal Sekali Transfer', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Text(
                          CurrencyFormatter.formatRupiah(minTransfer),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Proteksi Salah PIN / Password', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Text(
                          'Auto-Block 3x Percobaan',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFEA580C)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 4. Riwayat Pengajuan Deposito & Pinjaman Online Saya
              const Text(
                'Status Pengajuan Deposito & Pinjaman Saya',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_myApplications.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Belum ada pengajuan pembukaan Deposito atau Pinjaman baru.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                )
              else
                ..._myApplications.map((app) {
                  final status = (app['status']?.toString() ?? 'PENDING').toUpperCase();
                  final amount = (app['amount'] is num) ? (app['amount'] as num).toDouble() : 0.0;
                  final tenor = app['tenor_months']?.toString() ?? '-';
                  final notes = app['admin_notes']?.toString() ?? '';
                  Color badgeBg = const Color(0xFFFEF3C7);
                  Color badgeText = const Color(0xFFB45309);
                  String statusLabel = 'MENUNGGU VERIFIKASI CS';
                  if (status == 'CONTACTED') {
                    badgeBg = const Color(0xFFDBEAFE);
                    badgeText = const Color(0xFF1D4ED8);
                    statusLabel = 'SEDANG DIPROSES CS';
                  } else if (status == 'APPROVED') {
                    badgeBg = const Color(0xFFDCFCE7);
                    badgeText = const Color(0xFF15803D);
                    statusLabel = 'DISETUJUI';
                  } else if (status == 'REJECTED') {
                    badgeBg = const Color(0xFFFFE4E6);
                    badgeText = const Color(0xFFBE123C);
                    statusLabel = 'BELUM DISETUJUI';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                app['product_name']?.toString() ?? 'Produk Bank DMB',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                              child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badgeText)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Nominal: ${CurrencyFormatter.formatRupiah(amount)}  •  Tenor: $tenor Bulan',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Catatan CS: "$notes"',
                            style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 24),

              // 5. Pusat Bantuan Resmi Bank DMB
              const Text(
                'Pusat Bantuan & Layanan Nasabah',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bankConfig['bank_name']?.toString() ?? 'PT BPR DANA MANDIRI BOGOR',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _bankConfig['head_office_address']?.toString() ?? 'Jl. Pajajaran No. 88, Bogor, Jawa Barat',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const Divider(height: 22),
                    _buildContactRow(Icons.call_rounded, 'Call Center Resmi', _bankConfig['call_center']?.toString() ?? '(0251) 832-1234'),
                    const SizedBox(height: 10),
                    _buildContactRow(Icons.chat_bubble_outline_rounded, 'WhatsApp CS Bank DMB', _bankConfig['whatsapp_cs']?.toString() ?? '081199887766'),
                    const SizedBox(height: 10),
                    _buildContactRow(Icons.email_outlined, 'Email Pengaduan Nasabah', _bankConfig['email_cs']?.toString() ?? 'layanan@bprdanamandiribogor.co.id'),
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

  Widget _buildContactRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

