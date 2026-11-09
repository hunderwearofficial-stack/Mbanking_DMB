import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/mutation_model.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../auth/login_screen.dart';
import '../mutation/mutation_screen.dart';
import '../notification/notification_screen.dart';
import 'widgets/balance_card.dart';
import 'widgets/quick_menu_grid.dart';
import 'widgets/promo_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _uploadedLogoUrl = '';

  @override
  void initState() {
    super.initState();
    context.read<AccountCubit>().loadDashboardData();
    _loadBankConfig();
  }

  Future<void> _loadBankConfig() async {
    try {
      final apiClient = context.read<AccountCubit>().accountRepository.apiClient;
      final res = await apiClient.get('/api/v1/config');
      if (mounted && res is Map<String, dynamic>) {
        final logo = (res['logo_url'] as String?) ?? '';
        if (logo.isNotEmpty) {
          setState(() => _uploadedLogoUrl = logo);
        }
      }
    } catch (_) {}
  }

  void _onLogout() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Keluar dari Aplikasi?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sesi login Anda di Bank DMB akan diakhiri dengan aman. Anda dapat masuk kembali kapan saja.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.of(bottomSheetContext).pop(),
                      child: const Text(
                        'Batal',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.of(bottomSheetContext).pop();
                        context.read<AuthCubit>().logout();
                      },
                      child: const Text(
                        'Ya, Keluar',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionReceipt(BuildContext context, MutationModel m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
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
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: m.isCredit ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: m.isCredit ? const Color(0xFF86EFAC) : const Color(0xFFFECDD3),
                  ),
                ),
                child: Icon(
                  m.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  color: m.isCredit ? AppColors.primary : AppColors.expense,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                m.isCredit ? 'DANA MASUK (KREDIT)' : 'DANA KELUAR (DEBIT)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: m.isCredit ? AppColors.primary : AppColors.expense,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: m.isCredit ? AppColors.primary : AppColors.expense,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),
            _buildReceiptRow('Status Transaksi', 'BERHASIL (SUCCESS)', isHighlight: true),
            _buildReceiptRow('Waktu Transaksi', CurrencyFormatter.formatDateFull(m.createdAt)),
            _buildReceiptRow('Nomor Referensi', m.referenceNumber),
            _buildReceiptRow('Keterangan', m.description),
            _buildReceiptRow('Nomor Rekening', m.accountNumber),
            _buildReceiptRow('Saldo Setelahnya', CurrencyFormatter.formatRupiah(m.balanceAfter)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup Bukti Transaksi', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isHighlight ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCBSCustomerProfileModal(BuildContext context) {
    final accountRepo = context.read<AccountCubit>().accountRepository;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: FutureBuilder<List<dynamic>>(
            future: Future.wait([
              accountRepo.getCustomerProfile().catchError((_) => <String, dynamic>{}),
              accountRepo.getSavingsAccounts().catchError((_) => <Map<String, dynamic>>[]),
              accountRepo.apiClient.get(ApiEndpoints.cbsHealth).catchError((_) => <String, dynamic>{}),
            ]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text(
                        'Mengambil Data Nasabah & Portofolio dari CBS OpenAPI...',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }

              final profile = (snapshot.data != null && snapshot.data!.isNotEmpty && snapshot.data![0] is Map<String, dynamic>)
                  ? snapshot.data![0] as Map<String, dynamic>
                  : <String, dynamic>{};
              final accounts = (snapshot.data != null && snapshot.data!.length > 1 && snapshot.data![1] is List)
                  ? snapshot.data![1] as List
                  : <dynamic>[];
              final health = (snapshot.data != null && snapshot.data!.length > 2 && snapshot.data![2] is Map<String, dynamic>)
                  ? snapshot.data![2] as Map<String, dynamic>
                  : <String, dynamic>{};

              final cbsLatency = health['latency_ms']?.toString() ?? '-';
              final cbsConnected = health['reachable'] == true;

              return SingleChildScrollView(
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
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Profil Nasabah CBS',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                              ),
                              Text(
                                cbsConnected
                                    ? 'CBS OpenAPI Online ($cbsLatency ms)'
                                    : 'Sinkronisasi Core Banking BPR DMB',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildReceiptRow('Nomor CIF', profile['cif']?.toString() ?? '-'),
                    _buildReceiptRow('Nama Lengkap (CBS)', profile['nama']?.toString() ?? '-', isHighlight: true),
                    _buildReceiptRow('NIK / Identitas', profile['nik']?.toString() ?? '-'),
                    _buildReceiptRow('Tempat, Tgl Lahir', '${profile['tempat_lahir'] ?? '-'}, ${(profile['tgl_lahir']?.toString() ?? '-').split('T').first}'),
                    _buildReceiptRow('Ibu Kandung', profile['nama_ibu_kandung']?.toString() ?? '-'),
                    _buildReceiptRow('Agama', profile['agama']?.toString() ?? '-'),
                    _buildReceiptRow('Alamat CBS', '${profile['alamat'] ?? '-'} (${profile['kode_pos'] ?? '-'})'),
                    _buildReceiptRow('No. HP di CBS / DB Backdoor', 'CBS: ${profile['nohp'] ?? '0'} (Aktif via DB M-Banking)'),
                    if (accounts.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 8),
                      const Text(
                        'Portofolio Rekening di CIF Ini (/api/savings-accounts):',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      ...accounts.map((item) {
                        final map = item as Map<String, dynamic>;
                        final noRek = map['no_rek']?.toString() ?? '-';
                        final prod = map['kode_produk']?.toString() ?? '-';
                        final saldo = (map['saldo_akhir'] is num) ? (map['saldo_akhir'] as num).toDouble() : 0.0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(noRek, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                                  Text('Kode Produk CBS: $prod', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                              Text(
                                CurrencyFormatter.formatRupiah(saldo),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(modalCtx),
                        child: const Text('Tutup Profil CBS', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showQrisScannerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
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
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'QRIS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Bank DMB',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Arahkan kamera ke kode QRIS merchant untuk membayar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // Scanner Viewfinder
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 140, color: Colors.white.withOpacity(0.2)),
                  Container(
                    width: 170,
                    height: 2,
                    color: AppColors.primary.withOpacity(0.85),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildScannerAction(Icons.flash_on_rounded, 'Senter', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lampu senter diaktifkan'), behavior: SnackBarBehavior.floating),
                  );
                }),
                _buildScannerAction(Icons.photo_library_rounded, 'Galeri', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pilih foto QR dari galeri'), behavior: SnackBarBehavior.floating),
                  );
                }),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup Pemindai', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
              _loadBankConfig();
              await context.read<AccountCubit>().refresh();
            },
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Executive Top Header (Consistent with Backoffice)
                    _buildExecutiveHeader(),

                    const SizedBox(height: 14),

                    // 2. Luxury Wondr Balance Card (Tabungan DMB + Saldo + Copy + Detail)
                    BlocBuilder<AccountCubit, AccountState>(
                      builder: (context, state) {
                        if (state is AccountLoaded) {
                          return FigmaBalanceCardCarousel(
                            account: state.account,
                            isBalanceVisible: state.isBalanceVisible,
                            onToggleVisibility: () {
                              context.read<AccountCubit>().toggleBalanceVisibility();
                            },
                          );
                        }
                        return FigmaBalanceCardCarousel(
                          account: null,
                          isBalanceVisible: false,
                          onToggleVisibility: () {},
                        );
                      },
                    ),

                    const SizedBox(height: 6),

                    // 3. Grid "Fitur pilihan kamu" khas wondr by BNI
                    const FigmaMenuGrid(),

                    // 4. Promotional CMS Banners (Synced directly with Web Admin)
                    const FigmaPromoSection(),

                    // Extra bottom padding so floating QRIS pill doesn't block content
                    const SizedBox(height: 95),
                  ],
                ),
              ),
            ),
          ),

          // WONDR BY BNI STYLE: NO BOTTOM BAR! ONLY THE FLOATING QRIS PILL!
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: _buildWondrFloatingQrisPill(),
        ),
      ),
    );
  }

  /// Clean Executive Top Header matching wondr by BNI screenshot
  Widget _buildExecutiveHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 8),
      child: Column(
        children: [
          // Row 1: Uploaded Bank Logo on Left (auto-cropped from whitespace), Logout on Right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Official Uploaded Bank DMB Logo (dynamically synced from Web Backoffice /api/v1/config)
              _uploadedLogoUrl.isNotEmpty
                  ? Image.network(
                      _uploadedLogoUrl.startsWith('http')
                          ? _uploadedLogoUrl
                          : '${ApiEndpoints.baseUrl}$_uploadedLogoUrl',
                      height: 34,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/bank_logo.png',
                        height: 34,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                      ),
                    )
                  : Image.asset(
                      'assets/images/bank_logo.png',
                      height: 34,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                    ),

              // Right: Clean Exit / Logout Icon
              InkWell(
                onTap: _onLogout,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.logout_rounded, color: AppColors.textPrimary, size: 20),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Row 2: "Hi, Bima!" on Left, "Notifikasi" & "Bukti Transaksi" on Right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // User Greeting (Tap to open Live CBS Customer Profile & Portfolio)
              InkWell(
                onTap: () => _showCBSCustomerProfileModal(context),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle_outlined, color: AppColors.primary, size: 24),
                      const SizedBox(width: 6),
                      BlocBuilder<AccountCubit, AccountState>(
                        builder: (context, accState) {
                          return BlocBuilder<AuthCubit, AuthState>(
                            builder: (context, authState) {
                              String fullName = 'Nasabah';
                              if (accState is AccountLoaded && accState.account.holderName.isNotEmpty) {
                                fullName = accState.account.holderName;
                              } else if (authState is AuthAuthenticated && authState.user.fullName.isNotEmpty) {
                                fullName = authState.user.fullName;
                              }
                              final firstName = fullName.split(' ').first;
                              return Text(
                                'Hi, $firstName!',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Right: Two Actions (Notifikasi & Bukti Transaksi)
              Row(
                children: [
                  // Action 1: Notifikasi
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary, size: 22),
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEA580C), // Orange dot
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Notifikasi',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Action 2: Bukti Transaksi
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MutationScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, color: AppColors.textPrimary, size: 22),
                          SizedBox(height: 2),
                          Text(
                            'Bukti Transaksi',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Recent Mutations Feed with Tap to View Digital E-Receipt
  Widget _buildRecentMutationsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Mutasi transaksi kamu',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MutationScreen()),
                  );
                },
                child: const Row(
                  children: [
                    Text(
                      'Lihat semua',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFEA580C), // Orange like wondr
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFEA580C), size: 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          BlocBuilder<AccountCubit, AccountState>(
            builder: (context, state) {
              if (state is AccountLoaded && state.mutations.isNotEmpty) {
                final displayList = state.mutations.take(4).toList();
                return Column(
                  children: displayList.map((m) {
                    return InkWell(
                      onTap: () => _showTransactionReceipt(context, m),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: m.isCredit ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                m.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                color: m.isCredit ? AppColors.primary : AppColors.expense,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    CurrencyFormatter.formatDateShort(m.createdAt),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  (m.isCredit ? '+ ' : '- ') + CurrencyFormatter.formatRupiah(m.amount),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: m.isCredit ? AppColors.primary : AppColors.expense,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 10),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'Belum ada transaksi pada periode ini',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// WONDR BY BNI SIGNATURE: THE FLOATING BLACK QRIS PILL
  Widget _buildWondrFloatingQrisPill() {
    return InkWell(
      onTap: () => _showQrisScannerModal(context),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF111827), // Deep Obsidian Charcoal Black as in Wondr
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Stylized QRIS badge graphic
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF111827), size: 14),
            ),
            const SizedBox(width: 8),
            const Text(
              'QRIS',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
