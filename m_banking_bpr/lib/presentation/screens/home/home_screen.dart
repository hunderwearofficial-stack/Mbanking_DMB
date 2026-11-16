import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../auth/login_screen.dart';
import '../notification/notification_screen.dart';
import '../profile/security_settings_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../profile/profile_screen.dart';
import 'widgets/quick_menu_grid.dart';
import '../../../core/content/app_content.dart';
import '../../../core/services/fcm_service.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../core/money/money.dart';
import '../../widgets/smart_security_capsule.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../../core/services/dynamic_config_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0;
  bool _isBalanceVisible = false; // Persistent balance visibility (default hidden, preserves across refresh)
  int _unreadNotifications = 0; // Dynamic unread notification counter for red dot badge

  // Cached live values so during refresh (pull-to-refresh) the screen NEVER flashes fake numbers
  Money? _cachedBalance;
  String? _cachedAccountNo;
  String? _cachedUserName;

  // Banner Carousel State (3 Sessions auto-sliding)
  final PageController _promoPageController = PageController();
  int _currentPromoPage = 0;
  Timer? _promoTimer;

  // Executive Brand Colors
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _startPromoTimer();
    context.read<AccountCubit>().loadDashboardData();
    _checkUnreadNotifications();

    // Ensure FCM Token is actively synced to backend when dashboard loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final authRepo = context.read<AuthRepository>();
        FCMService().syncStoredTokenIfLoggedIn(apiClient: authRepo.apiClient);
      } catch (_) {}
    });
  }

  int get _visibleBannerCount =>
      _bannerSlots.where((s) => AppContent.flag('home.banner${s.number}_visible')).length;

  void _onBannerAction(String action) {
    switch (action) {
      case 'profil':
        setState(() => _currentNavIndex = 1);
        break;
      case 'keamanan':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()));
        break;
      default:
        break;
    }
  }

  void _startPromoTimer() {
    _promoTimer?.cancel();
    _promoTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      if (_promoPageController.hasClients) {
        final count = _visibleBannerCount;
        if (count < 2) return;
        final nextPage = (_currentPromoPage + 1) % count;
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

  Future<void> _checkUnreadNotifications() async {
    try {
      final repo = context.read<AccountCubit>().accountRepository;
      final list = await repo.getNotifications(limit: 20);
      final unread = list.where((n) => n['is_read'] != true).length;
      if (mounted) {
        setState(() {
          _unreadNotifications = unread;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _unreadNotifications = 0);
      }
    }
  }

  void _showToast(String msg) {
    AppToast.showInfo(context, msg);
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
        // null = balance not (successfully) obtained: never render a placeholder number.
        Money? balance = _cachedBalance;

        if (authState is AuthAuthenticated) {
          if (userName.isEmpty && authState.user.fullName.isNotEmpty) {
            userName = authState.user.fullName;
          }
          if (rawAccountNo.isEmpty && authState.user.primaryAccount.isNotEmpty) {
            rawAccountNo = authState.user.primaryAccount;
          }
        }
        if (userName.isEmpty) userName = 'Nasabah Bank DMB';

        if (state is AccountError) {
          balance = null;
          _cachedBalance = null;
        }
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
                  final error = await context.read<AccountCubit>().refresh();
                  if (error != null && context.mounted) {
                    AppToast.showWarning(context, 'Saldo belum dapat diperbarui. $error', title: 'Pemberitahuan');
                  }
                },
                color: primaryNavy,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Top: Smart Security Capsule, Sapaan & Action Icons
                      _buildTopHeader(userName, rawAccountNo),

                      _buildAnnouncementBanner(),

                      const SizedBox(height: 16),

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

                      const SizedBox(height: 18),

                      // Banner Promo / Iklan (Dipindah ke atas menu utama)
                      _buildPromoBanner(),

                      const SizedBox(height: 18),

                      // Menu Utama Resmi Core Banking DMB (8 Menu Lengkap Terintegrasi Live API)
                      const FigmaMenuGrid(),

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

  // ==================== 1. TOP HEADER WITH SMART SECURITY CAPSULE ====================
  Widget _buildTopHeader(String userName, String rawAccountNo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Upper Status Bar: Smart Security Capsule + Action Icons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Smart Security Capsule (Bank DMB Connected / Offline Indicator)
            SmartSecurityCapsule(
              customerName: userName,
              accountNumber: rawAccountNo,
            ),

            // Top Action Icons: Bantuan, Pengaturan, Notifikasi
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Pusat Bantuan (Helpdesk)
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
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
                      Icons.headset_mic_outlined,
                      color: titleDark,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Pengaturan (Settings)
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
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
                      Icons.settings_outlined,
                      color: titleDark,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Notification Bell Icon with Dynamic Red Dot Badge (Only shown if unread > 0)
                InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NotificationScreen()),
                    );
                    _checkUnreadNotifications();
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
                          size: 20,
                        ),
                      ),
                      if (_unreadNotifications > 0)
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
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Greeting & Name
        Text(
          AppContent.text('home.greeting_title'),
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
          AppContent.text('home.greeting_subtitle'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF1E3A6E), // Deep Navy-Blue tone, definitely NOT washed-out grey
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  // ==================== LIVE ANNOUNCEMENT BANNER ====================
  Widget _buildAnnouncementBanner() {
    return ListenableBuilder(
      listenable: DynamicConfigService(),
      builder: (context, _) {
        final text = AppContent.text('app.announcement').trim();
        if (text.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBF7D0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16984B).withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16984B).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Color(0xFF16984B),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0F172A),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== 2. MAIN SALDO CARD (NEW DESIGN) ====================
  Widget _buildMainBalanceCard({
    required Money? balance,
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
                    balance == null
                        ? 'Saldo belum dapat ditampilkan'
                        : isBalanceVisible
                            ? CurrencyFormatter.formatRupiah(balance)
                            : 'Rp •••••••••',
                    style: TextStyle(
                      fontSize: balance == null ? 15 : 27,
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

  // ==================== 5. PROMO BANNER CAROUSEL (3 SESSIONS) ====================
  Widget _buildPromoBanner() {
    if (_promoTimer == null || !_promoTimer!.isActive) {
      _startPromoTimer();
    }
    // 3 carousel slots; visibility, image, fallback texts and tap action are managed content
    // (Backoffice → Konten Aplikasi → Beranda). Slots keep their bundled image and colours.
    final banners = <_PromoBannerData>[
      for (final slot in _bannerSlots)
        if (AppContent.flag('home.banner${slot.number}_visible'))
          _PromoBannerData(
            imagePath: slot.asset,
            imageUrl: AppContent.imageUrl('home.banner${slot.number}_image'),
            title: AppContent.text('home.banner${slot.number}_title'),
            subtitle: AppContent.text('home.banner${slot.number}_subtitle'),
            gradientColors: slot.gradient,
            onTap: () => _onBannerAction(AppContent.text('home.banner${slot.number}_action')),
          ),
    ];
    if (banners.isEmpty) return const SizedBox.shrink();
    if (_currentPromoPage >= banners.length) _currentPromoPage = 0;

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
                      child: item.imageUrl != null
                          ? Image.network(
                              item.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Image.asset(
                                item.imagePath,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Image.asset(
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

  // ==================== 6. BOTTOM NAVIGATION BAR (2 TABS: BERANDA & PROFIL) ====================
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
              _buildNavItem(1, Icons.person_outline_rounded, 'Profil'),
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

class _BannerSlot {
  final int number;
  final String asset;
  final List<Color> gradient;
  const _BannerSlot(this.number, this.asset, this.gradient);
}

const _bannerSlots = [
  _BannerSlot(1, 'assets/images/banner_promo_1.jpg', [Color(0xFFE8F7F2), Color(0xFFE0F2FE)]),
  _BannerSlot(2, 'assets/images/banner_promo_2.jpg', [Color(0xFFEBF7F0), Color(0xFFE1F5FE)]),
  _BannerSlot(3, 'assets/images/banner_promo_3.jpg', [Color(0xFFE8EEF8), Color(0xFFE5F5F0)]),
];

class _PromoBannerData {
  final String imagePath;
  final String? imageUrl;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _PromoBannerData({
    required this.imagePath,
    this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });
}
