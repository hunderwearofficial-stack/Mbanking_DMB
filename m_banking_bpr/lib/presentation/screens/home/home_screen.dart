import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../profile/security_settings_screen.dart';
import '../account/account_info_screen.dart';
import '../statement/estatement_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0;
  bool _maintenanceMode = false;
  String _maintenanceMessage = '';
  bool _isBalanceVisible = false; // Persistent balance visibility (default hidden, preserves across refresh)

  // Cached live values so during refresh (pull-to-refresh) the screen NEVER flashes fake numbers
  double? _cachedBalance;
  String? _cachedAccountNo;
  String? _cachedUserName;

  // Banner Carousel State (3 Sessions auto-sliding)
  final PageController _promoPageController = PageController();
  int _currentPromoPage = 0;
  Timer? _promoTimer;

  // Executive Brand Colors
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _startPromoTimer();
    context.read<AccountCubit>().loadDashboardData();
    _loadBankConfig();
  }

  void _startPromoTimer() {
    _promoTimer?.cancel();
    _promoTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      if (_promoPageController.hasClients) {
        final nextPage = (_currentPromoPage + 1) % 3;
        _promoPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _promoTimer?.cancel();
    _promoPageController.dispose();
    super.dispose();
  }

  Future<void> _loadBankConfig() async {
    try {
      final apiClient = context.read<AccountCubit>().accountRepository.apiClient;
      final res = await apiClient.get('/api/v1/config');
      if (mounted && res is Map<String, dynamic>) {
        setState(() {
          _maintenanceMode = res['maintenance_mode'] == true;
          _maintenanceMessage = (res['maintenance_message'] as String?) ?? '';
        });
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
                  color: borderLight,
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
                child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Keluar dari Aplikasi?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sesi login Anda di Bank DMB akan diakhiri dengan aman. Anda dapat masuk kembali kapan saja.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: textMuted, height: 1.45),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textMuted,
                        side: const BorderSide(color: borderLight),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(bottomSheetContext),
                      child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(bottomSheetContext);
                        context.read<AuthCubit>().logout();
                      },
                      child: const Text('Ya, Keluar', style: TextStyle(fontWeight: FontWeight.w700)),
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

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
        backgroundColor: titleDark,
      ),
    );
  }

  String _formatAccountNumber(String raw) {
    if (raw.isEmpty) return '-';
    final cleaned = raw.replaceAll(RegExp(r'\D'), '');
    if (cleaned.isEmpty) return raw;
    final buffer = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(cleaned[i]);
    }
    return buffer.toString();
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
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: PopScope(
          canPop: _currentNavIndex == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _currentNavIndex != 0) {
              setState(() => _currentNavIndex = 0);
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: IndexedStack(
              index: _currentNavIndex,
              children: [
                _buildHomeContent(),
                const AccountInfoScreen(isTab: true),
                const HelpdeskScreen(isTab: true),
                const ProfileScreen(isTab: true),
              ],
            ),
            bottomNavigationBar: _buildBottomNavigationBar(),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return BlocBuilder<AccountCubit, AccountState>(
      builder: (context, state) {
        final authState = context.watch<AuthCubit>().state;
        String userName = _cachedUserName ?? '';
        String rawAccountNo = _cachedAccountNo ?? '';
        double balance = _cachedBalance ?? 0.0;
        List<MutationModel> mutations = [];

        if (authState is AuthAuthenticated) {
          if (userName.isEmpty && authState.user.fullName.isNotEmpty) {
            userName = authState.user.fullName;
          }
          if (rawAccountNo.isEmpty && authState.user.primaryAccount.isNotEmpty) {
            rawAccountNo = authState.user.primaryAccount;
          }
        }
        if (userName.isEmpty) userName = 'Nasabah Bank DMB';

        if (state is AccountLoaded) {
          balance = state.account.balance;
          _cachedBalance = balance;

          if (state.account.accountNumber.isNotEmpty) {
            rawAccountNo = state.account.accountNumber;
            _cachedAccountNo = rawAccountNo;
          }
          if (state.account.holderName.isNotEmpty) {
            userName = state.account.holderName;
            _cachedUserName = userName;
          }
          mutations = state.mutations;
        }

        final formattedAccountNo = _formatAccountNumber(rawAccountNo);

        return Stack(
          children: [
            // 1. Mount Salak & Sky Artwork Backdrop at top
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 250,
              child: Opacity(
                opacity: 0.85,
                child: Image.asset(
                  'assets/images/splash_artwork.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),

            // Soft gradient fade into white body
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 260,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.40, 0.85, 1.0],
                    colors: [
                      Colors.white.withOpacity(0.10),
                      Colors.white.withOpacity(0.55),
                      const Color(0xFFF8FAFC).withOpacity(0.95),
                      const Color(0xFFF8FAFC),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Main Scrollable Content
            SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  _loadBankConfig();
                  await context.read<AccountCubit>().refresh();
                },
                color: primaryNavy,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Top: Sapaan & Notification Bell
                      _buildTopHeader(userName),

                      const SizedBox(height: 18),

                      // Main Saldo Card (Ocean-Green Gradient Card per new mockup)
                      _buildMainBalanceCard(
                        balance: balance,
                        accountNoFormatted: formattedAccountNo,
                        rawAccountNo: rawAccountNo,
                        isBalanceVisible: _isBalanceVisible,
                        onToggleVisibility: () {
                          setState(() {
                            _isBalanceVisible = !_isBalanceVisible;
                          });
                          context.read<AccountCubit>().toggleBalanceVisibility();
                        },
                      ),

                      const SizedBox(height: 22),

                      // Menu Utama (4 Quick Action Buttons)
                      _buildMenuUtamaSection(),

                      const SizedBox(height: 20),

                      // Banner Promo (Akses informasi rekening lebih mudah)
                      _buildPromoBanner(),

                      // Extra bottom padding for bottom navigation bar
                      const SizedBox(height: 90),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==================== 1. TOP HEADER ====================
  Widget _buildTopHeader(String userName) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Greeting & Name
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selamat Datang,',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0B2A63),
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 1.5),
            Row(
              children: [
                Text(
                  userName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18.0,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF072152),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 5),
                const Text('👋', style: TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 2.5),
            Text(
              'Semoga harimu menyenangkan!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1E3A6E), // Deep Navy-Blue tone, definitely NOT washed-out grey
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),

        // Notification Bell Icon with Red Dot Badge
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  shape: BoxShape.circle,
                  border: Border.all(color: borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: titleDark,
                  size: 22,
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 2. MAIN SALDO CARD (NEW DESIGN) ====================
  Widget _buildMainBalanceCard({
    required double balance,
    required String accountNoFormatted,
    required String rawAccountNo,
    required bool isBalanceVisible,
    required VoidCallback onToggleVisibility,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 195),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0754A8).withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Official Card Template Image provided by User
            Positioned.fill(
              child: Image.asset(
                'assets/images/Card.png',
                fit: BoxFit.fill,
              ),
            ),

            // Card Foreground Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Row: (Rekening Utama + Copy) on Left, (Realistic ATM Chip) on Right
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left: Card Icon + Rekening Utama + Copy Icon
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: rawAccountNo));
                          _showToast('Nomor rekening disalin: $rawAccountNo');
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withOpacity(0.30)),
                              ),
                              child: const Icon(
                                Icons.credit_card_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rekening Utama',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      accountNoFormatted,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.copy_rounded,
                                      color: Colors.white.withOpacity(0.85),
                                      size: 15,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Right: Authentic Gold EMV ATM Chip
                      _buildAtmChip(),
                    ],
                  ),

                  const SizedBox(height: 26),

                  // Middle Row: Saldo Tersedia + Eye Toggle
                  Row(
                    children: [
                      Text(
                        'Saldo Tersedia',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.90),
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onToggleVisibility,
                        child: Icon(
                          isBalanceVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.white.withOpacity(0.90),
                          size: 17,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Big Balance Nominal
                  Text(
                    isBalanceVisible
                        ? CurrencyFormatter.formatRupiah(balance)
                        : 'Rp •••••••••',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
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

  // ==================== AUTHENTIC GOLD EMV ATM CHIP ====================
  Widget _buildAtmChip() {
    return Container(
      width: 44,
      height: 33,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE79A), // Golden highlight
            Color(0xFFE2B246), // Classic Gold
            Color(0xFFB57E14), // Deep metallic bronze gold
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFFFEDB3), width: 0.8),
      ),
      child: Stack(
        children: [
          // Inner frame
          Positioned(
            left: 3.5,
            right: 3.5,
            top: 3.5,
            bottom: 3.5,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF6E4A00).withOpacity(0.40), width: 0.7),
              ),
            ),
          ),
          // Horizontal contact division
          Positioned(
            left: 0,
            right: 0,
            top: 15.5,
            child: Container(
              height: 0.8,
              color: const Color(0xFF6E4A00).withOpacity(0.40),
            ),
          ),
          // Left contact division
          Positioned(
            left: 13,
            top: 0,
            bottom: 0,
            child: Container(
              width: 0.8,
              color: const Color(0xFF6E4A00).withOpacity(0.40),
            ),
          ),
          // Right contact division
          Positioned(
            right: 13,
            top: 0,
            bottom: 0,
            child: Container(
              width: 0.8,
              color: const Color(0xFF6E4A00).withOpacity(0.40),
            ),
          ),
          // Central contact pad
          Positioned(
            left: 13,
            right: 13,
            top: 8.5,
            bottom: 8.5,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0B8).withOpacity(0.40),
                border: Border.all(color: const Color(0xFF6E4A00).withOpacity(0.40), width: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 3. MENU UTAMA (4 QUICK MENUS) ====================
  Widget _buildMenuUtamaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Menu Utama',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: titleDark,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Informasi Rekening
            Expanded(
              child: _buildMenuUtamaItem(
                icon: Icons.article_outlined,
                label: 'Informasi\nRekening',
                onTap: () {
                  setState(() => _currentNavIndex = 1);
                },
              ),
            ),

            // 2. Riwayat Transaksi
            Expanded(
              child: _buildMenuUtamaItem(
                icon: Icons.history_rounded,
                label: 'Riwayat\nTransaksi',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MutationScreen()),
                  );
                },
              ),
            ),

            // 3. e-Statement
            Expanded(
              child: _buildMenuUtamaItem(
                icon: Icons.receipt_long_outlined,
                label: 'e-Statement',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EStatementScreen()),
                  );
                },
              ),
            ),

            // 4. Pusat Bantuan
            Expanded(
              child: _buildMenuUtamaItem(
                icon: Icons.headset_mic_outlined,
                label: 'Pusat\nBantuan',
                onTap: () {
                  setState(() => _currentNavIndex = 2);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuUtamaItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF3F8FE),
                  Color(0xFFE8F1FC),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD6E6F9)),
              boxShadow: [
                BoxShadow(
                  color: royalBlue.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: royalBlue, size: 24),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 32,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 5. PROMO BANNER CAROUSEL (3 SESSIONS) ====================
  Widget _buildPromoBanner() {
    if (_promoTimer == null || !_promoTimer!.isActive) {
      _startPromoTimer();
    }
    final banners = [
      _PromoBannerData(
        imagePath: 'assets/images/banner_promo_1.jpg',
        title: 'DMB Mobile',
        subtitle: 'Lebih Mudah, Lebih Dekat dengan Anda',
        gradientColors: const [Color(0xFFE8F7F2), Color(0xFFE0F2FE)],
        onTap: () {
          setState(() => _currentNavIndex = 1);
        },
      ),
      _PromoBannerData(
        imagePath: 'assets/images/banner_promo_2.jpg',
        title: 'Tabungan Mikro DMB',
        subtitle: 'Bunga Kompetitif, Aman & Dijamin LPS',
        gradientColors: const [Color(0xFFEBF7F0), Color(0xFFE1F5FE)],
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
          );
        },
      ),
      _PromoBannerData(
        imagePath: 'assets/images/banner_promo_3.jpg',
        title: 'Keamanan Berlapis',
        subtitle: 'Proteksi PIN & OTP untuk Setiap Transaksi',
        gradientColors: const [Color(0xFFE8EEF8), Color(0xFFE5F5F0)],
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
          );
        },
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 165,
          child: PageView.builder(
            controller: _promoPageController,
            itemCount: banners.length,
            onPageChanged: (index) {
              setState(() {
                _currentPromoPage = index;
              });
            },
            itemBuilder: (context, index) {
              final item = banners[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: item.onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: royalBlue.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        item.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Clean fallback card if asset fails or loading
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: item.gradientColors,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFD6E8F8)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        item.title,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: titleDark,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.subtitle,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Image.asset(
                                  'assets/images/bank_logo.png',
                                  width: 44,
                                  height: 44,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.campaign_rounded,
                                    size: 36,
                                    color: royalBlue,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Carousel 3-session indicator dots (Pill for active, circles for inactive)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(banners.length, (index) {
            final isActive = _currentPromoPage == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive ? royalBlue : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ==================== 6. BOTTOM NAVIGATION BAR (4 TABS) ====================
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, 'Beranda'),
              _buildNavItem(1, Icons.article_outlined, 'Informasi'),
              _buildNavItem(2, Icons.headset_mic_outlined, 'Bantuan'),
              _buildNavItem(3, Icons.person_outline_rounded, 'Profil'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentNavIndex == index;
    return InkWell(
      onTap: () {
        setState(() => _currentNavIndex = index);
      },
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? royalBlue : const Color(0xFF64748B),
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? royalBlue : const Color(0xFF64748B),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 3),
              Container(
                width: 18,
                height: 2.5,
                decoration: BoxDecoration(
                  color: royalBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ] else ...[
              const SizedBox(height: 5.5),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromoBannerData {
  final String imagePath;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _PromoBannerData({
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });
}
