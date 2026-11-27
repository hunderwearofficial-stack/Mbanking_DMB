import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/money/money.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/mutation_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import '../account/account_info_screen.dart';
import '../auth/login_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../mutation/mutation_screen.dart';
import '../notification/notification_screen.dart';
import '../product/apply_hub_screen.dart';
import '../profile/company_profile_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/security_settings_screen.dart';
import 'widgets/quick_menu_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentNavIndex = 0;
  int _unreadNotifications = 0;

  Money? _cachedBalance;
  String? _cachedAccountNo;
  String? _cachedUserName;

  final PageController _promoPageController = PageController(viewportFraction: 1.0);
  int _currentPromoPage = 0;
  Timer? _promoTimer;
  StreamSubscription<void>? _fcmSub;
  DateTime? _lastAutoRefreshAt;

  static const Color deepCobalt = Color(0xFF033172);
  static const Color royalBlue = Color(0xFF0550A6);
  static const Color titleDark = Color(0xFF0F172A);
  static const Color canvasBg = Color(0xFFF4F7FB);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPromoTimer();
    context.read<AccountCubit>().loadDashboardData();
    _checkUnreadNotifications();

    _fcmSub = FCMService().onForegroundNotification.listen((_) => _triggerEventRefresh());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final authRepo = context.read<AuthRepository>();
        FCMService().syncStoredTokenIfLoggedIn(apiClient: authRepo.apiClient);
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerEventRefresh();
    }
  }

  void _triggerEventRefresh() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastAutoRefreshAt != null && now.difference(_lastAutoRefreshAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastAutoRefreshAt = now;
    context.read<AccountCubit>().loadDashboardData();
    _checkUnreadNotifications();
  }

  int get _visibleBannerCount =>
      _bannerSlots.where((s) => AppContent.flag('home.banner${s.number}_visible')).length;

  void _onBannerAction(String action) {
    switch (action) {
      case 'profil':
        setState(() => _currentNavIndex = 3);
        break;
      case 'keamanan':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()));
        break;
      default:
        setState(() => _currentNavIndex = 2);
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
    _fcmSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
    AppToast.showSuccess(context, msg);
  }

  String _formatAccountNumber(String raw) {
    if (raw.isEmpty || raw == '-') return '-';
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
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
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
            backgroundColor: canvasBg,
            body: IndexedStack(
              index: _currentNavIndex,
              children: [
                _buildHomeContent(),
                const SizedBox.shrink(),
                const CompanyProfileScreen(),
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
        final accountCubit = context.read<AccountCubit>();
        final authState = context.watch<AuthCubit>().state;
        String userName = _cachedUserName ?? '';
        String rawAccountNo = _cachedAccountNo ?? '';
        Money? balance = _cachedBalance;
        bool isBalanceVisible = accountCubit.isBalanceVisible;
        List<MutationModel> recentMutations = const [];

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
          isBalanceVisible = state.isBalanceVisible;
          recentMutations = state.mutations;

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
            // Deep Bank DMB Navy Architectural Header (blended with real Bank DMB building)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 255,
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/home_header_landmark.jpg',
                        fit: BoxFit.cover,
                        alignment: Alignment.topRight,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              deepCobalt.withValues(alpha: 0.96),
                              deepCobalt.withValues(alpha: 0.85),
                              royalBlue.withValues(alpha: 0.36),
                            ],
                            stops: const [0.0, 0.48, 1.0],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              deepCobalt.withValues(alpha: 0.72),
                              Colors.transparent,
                              deepCobalt.withValues(alpha: 0.55),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: () async {
                  final error = await context.read<AccountCubit>().refresh();
                  await _checkUnreadNotifications();
                  if (error != null && context.mounted) {
                    AppToast.showWarning(
                      context,
                      'Saldo belum dapat diperbarui. $error',
                      title: 'Pemberitahuan',
                    );
                  }
                },
                color: deepCobalt,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopHeader(userName),

                      _buildAnnouncementBanner(),

                      const SizedBox(height: 16),

                      _buildMainBalanceCard(
                        balance: balance,
                        accountNoFormatted: formattedAccountNo,
                        rawAccountNo: rawAccountNo,
                        isBalanceVisible: isBalanceVisible,
                        onToggleVisibility: () {
                          context.read<AccountCubit>().toggleBalanceVisibility();
                          setState(() {});
                        },
                      ),

                      const SizedBox(height: 20),

                      _buildPromoBanner(),

                      const SizedBox(height: 22),

                      const FigmaMenuGrid(),

                      const SizedBox(height: 22),

                      _buildRecentActivitySection(recentMutations),
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

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AuthUiTokens.softBlueBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: AuthUiTokens.softBlueBorder),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: deepCobalt,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Keluar dari Akun?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Anda perlu masuk kembali untuk mengakses layanan Mobile Banking.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(23),
                          ),
                        ),
                        child: const Text(
                          'Batal',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          context.read<AuthCubit>().logout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: deepCobalt,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(23),
                          ),
                        ),
                        child: const Text(
                          'Keluar',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
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

  Widget _buildTopHeader(String userName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const MyDmbBrandLogo(height: 38, onDark: true),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTopActionIcon(
                  icon: Icons.headset_mic_rounded,
                  tooltip: 'Pusat Bantuan',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                    );
                  },
                ),
                const SizedBox(width: 4),
                _buildTopActionIcon(
                  icon: Icons.notifications_rounded,
                  tooltip: 'Notifikasi',
                  badgeCount: _unreadNotifications,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NotificationScreen()),
                    );
                    _checkUnreadNotifications();
                  },
                ),
                const SizedBox(width: 4),
                _buildTopActionIcon(
                  icon: Icons.logout_rounded,
                  tooltip: 'Keluar',
                  onTap: _confirmLogout,
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 18),

        Text(
          AppContent.text('home.greeting_title'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.verified_rounded,
              color: Color(0xFF00E5FF),
              size: 18,
            ),
          ],
        ),
        if (AppContent.text('home.greeting_subtitle').trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            AppContent.text('home.greeting_subtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
        if (AppContent.text('home.greeting_note').trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            AppContent.text('home.greeting_note'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopActionIcon({
    required IconData icon,
    required String tooltip,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: Colors.white, size: 21),
                if (badgeCount > 0)
                  Positioned(
                    top: 3,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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

  Widget _buildAnnouncementBanner() {
    return ListenableBuilder(
      listenable: DynamicConfigService(),
      builder: (context, _) {
        final text = AppContent.text('app.announcement').trim();
        if (text.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AuthUiTokens.softBlueBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AuthUiTokens.softBlueBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign_rounded, color: royalBlue, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: titleDark,
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

  Widget _buildMainBalanceCard({
    required Money? balance,
    required String accountNoFormatted,
    required String rawAccountNo,
    required bool isBalanceVisible,
    required VoidCallback onToggleVisibility,
  }) {
    final canCopy = rawAccountNo.isNotEmpty && rawAccountNo != '-';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: deepCobalt,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: deepCobalt.withOpacity(0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
              );
            },
            child: Stack(
              children: [
                // Subtle translucent curve accent on the right
                Positioned(
                  right: -40,
                  top: -35,
                  child: Container(
                    width: 155,
                    height: 155,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: -48,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF118CE0).withOpacity(0.18),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Saldo Rekening Utama',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.84),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: onToggleVisibility,
                            child: Icon(
                              isBalanceVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.white.withOpacity(0.85),
                              size: 17,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        balance == null
                            ? 'Saldo belum tersedia'
                            : isBalanceVisible
                                ? CurrencyFormatter.formatRupiah(balance)
                                : 'Rp ••••••••',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: balance == null ? 16 : 25,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: canCopy
                            ? () {
                                Clipboard.setData(ClipboardData(text: rawAccountNo));
                                _showToast('Nomor rekening disalin: $rawAccountNo');
                              }
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.credit_card_rounded,
                              color: Color(0xFF00E5FF),
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                accountNoFormatted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.86),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            if (canCopy) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.copy_rounded,
                                color: Colors.white.withOpacity(0.68),
                                size: 13,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.16),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Lihat Semua Rekening',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(0.95),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromoBanner() {
    if (_promoTimer == null || !_promoTimer!.isActive) {
      _startPromoTimer();
    }
    final banners = <_PromoBannerData>[
      for (final slot in _bannerSlots)
        if (AppContent.flag('home.banner${slot.number}_visible'))
          _PromoBannerData(
            contentKey: 'home.banner${slot.number}_image',
            tag: AppContent.text('home.banner${slot.number}_tag'),
            title: AppContent.text('home.banner${slot.number}_title'),
            subtitle: AppContent.text('home.banner${slot.number}_subtitle'),
            onTap: () => _onBannerAction(AppContent.text('home.banner${slot.number}_action')),
          ),
    ];

    final effectiveBanners = banners.isNotEmpty
        ? banners
        : [
            _PromoBannerData(
              contentKey: '',
              tag: 'PERENCANAAN',
              title: 'Wujudkan Rencana Finansial Anda bersama DMB',
              subtitle: 'Pelajari Selengkapnya',
              onTap: () => setState(() => _currentNavIndex = 3),
            ),
          ];

    if (_currentPromoPage >= effectiveBanners.length) _currentPromoPage = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 94,
          child: PageView.builder(
            controller: _promoPageController,
            itemCount: effectiveBanners.length,
            onPageChanged: (index) {
              setState(() => _currentPromoPage = index);
            },
            itemBuilder: (context, index) {
              final item = effectiveBanners[index];
              final hasRemoteImage =
                  item.contentKey.isNotEmpty && AppContent.imageUrl(item.contentKey) != null;

              return GestureDetector(
                onTap: item.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: hasRemoteImage ? deepCobalt : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: hasRemoteImage
                        ? null
                        : Border.all(color: const Color(0xFFE8EEF6)),
                    boxShadow: [
                      BoxShadow(
                        color: royalBlue.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasRemoteImage) ...[
                          ContentImage(
                            item.contentKey,
                            fit: BoxFit.cover,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  deepCobalt,
                                  deepCobalt.withValues(alpha: 0.88),
                                  deepCobalt.withValues(alpha: 0.15),
                                ],
                                stops: const [0.0, 0.52, 1.0],
                              ),
                            ),
                          ),
                        ] else
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _PromoCardAccentPainter(),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.title.trim().isNotEmpty
                                          ? item.title
                                          : 'DMB Mobile',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: hasRemoteImage ? Colors.white : titleDark,
                                      ),
                                    ),
                                    if (item.subtitle.trim().isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        item.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: hasRemoteImage
                                              ? Colors.white.withValues(alpha: 0.85)
                                              : AuthUiTokens.textMuted,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Pelajari Selengkapnya',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: hasRemoteImage ? Colors.white : royalBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: hasRemoteImage ? Colors.white : royalBlue,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (effectiveBanners.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            children: List.generate(effectiveBanners.length, (index) {
              final isActive = _currentPromoPage == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                margin: const EdgeInsets.only(right: 5),
                width: isActive ? 20 : 6,
                height: 5,
                decoration: BoxDecoration(
                  color: isActive ? deepCobalt : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildRecentActivitySection(List<MutationModel> mutations) {
    final visible = mutations.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Aktivitas Terakhir',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MutationScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Lihat Semua',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: royalBlue,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, color: royalBlue, size: 17),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EEF6)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AuthUiTokens.softBlueBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: royalBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Belum ada aktivitas transaksi terbaru',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...visible.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MutationScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8EEF6)),
                    boxShadow: [
                      BoxShadow(
                        color: royalBlue.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AuthUiTokens.softBlueBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          m.isCredit
                              ? Icons.south_west_rounded
                              : Icons.north_east_rounded,
                          color: royalBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.description.trim().isNotEmpty
                                  ? m.description.trim()
                                  : 'Mutasi Rekening',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: titleDark,
                              ),
                            ),
                            if (m.createdAt.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                m.createdAt.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${m.isCredit ? '+' : '-'} ${CurrencyFormatter.formatRupiah(m.amount)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: m.isCredit
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE8EEF6))),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF033172).withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  type: _BottomNavType.home,
                  label: 'Beranda',
                  isSelected: _currentNavIndex == 0,
                  onTap: () => setState(() => _currentNavIndex = 0),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  type: _BottomNavType.apply,
                  label: 'Ajukan',
                  isSelected: false,
                  onTap: () => showApplyBottomSheet(context),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  type: _BottomNavType.bank,
                  label: 'DMB',
                  isSelected: _currentNavIndex == 2,
                  onTap: () => setState(() => _currentNavIndex = 2),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  type: _BottomNavType.account,
                  label: 'Akun',
                  isSelected: _currentNavIndex == 3,
                  onTap: () => setState(() => _currentNavIndex = 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required _BottomNavType type,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? AuthUiTokens.softBlueBg : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(
                painter: _BottomNavIconPainter(
                  type: type,
                  isSelected: isSelected,
                  activeColor: deepCobalt,
                  inactiveColor: const Color(0xFF64748B),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? deepCobalt : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

enum _BottomNavType { home, apply, bank, account }

class _BottomNavIconPainter extends CustomPainter {
  const _BottomNavIconPainter({
    required this.type,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
  });

  final _BottomNavType type;
  final bool isSelected;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()
      ..color = const Color(0xFF7DD3FC).withValues(alpha: isSelected ? 0.78 : 0.25)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = isSelected ? activeColor : inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 1.85 : 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case _BottomNavType.home:
        final house = Path()
          ..moveTo(w * 0.14, h * 0.44)
          ..lineTo(w * 0.50, h * 0.14)
          ..lineTo(w * 0.86, h * 0.44)
          ..lineTo(w * 0.86, h * 0.84)
          ..quadraticBezierTo(w * 0.86, h * 0.88, w * 0.80, h * 0.88)
          ..lineTo(w * 0.20, h * 0.88)
          ..quadraticBezierTo(w * 0.14, h * 0.88, w * 0.14, h * 0.84)
          ..close();
        canvas.drawPath(house, fill);
        canvas.drawPath(house, stroke);
        canvas.drawLine(Offset(w * 0.42, h * 0.88), Offset(w * 0.42, h * 0.62), stroke);
        canvas.drawLine(Offset(w * 0.42, h * 0.62), Offset(w * 0.58, h * 0.62), stroke);
        canvas.drawLine(Offset(w * 0.58, h * 0.62), Offset(w * 0.58, h * 0.88), stroke);
        break;

      case _BottomNavType.apply:
        final box = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.14, h * 0.14, w * 0.72, h * 0.72),
          const Radius.circular(6),
        );
        canvas.drawRRect(box, fill);
        canvas.drawRRect(box, stroke);
        canvas.drawLine(Offset(w * 0.50, h * 0.34), Offset(w * 0.50, h * 0.66), stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.50), Offset(w * 0.66, h * 0.50), stroke);
        break;

      case _BottomNavType.bank:
        final roof = Path()
          ..moveTo(w * 0.12, h * 0.38)
          ..lineTo(w * 0.50, h * 0.14)
          ..lineTo(w * 0.88, h * 0.38)
          ..close();
        canvas.drawPath(roof, fill);
        canvas.drawPath(roof, stroke);
        canvas.drawRect(Rect.fromLTWH(w * 0.22, h * 0.46, w * 0.56, h * 0.32), fill);
        canvas.drawLine(Offset(w * 0.26, h * 0.42), Offset(w * 0.26, h * 0.78), stroke);
        canvas.drawLine(Offset(w * 0.50, h * 0.42), Offset(w * 0.50, h * 0.78), stroke);
        canvas.drawLine(Offset(w * 0.74, h * 0.42), Offset(w * 0.74, h * 0.78), stroke);
        canvas.drawLine(Offset(w * 0.14, h * 0.84), Offset(w * 0.86, h * 0.84), stroke);
        break;

      case _BottomNavType.account:
        canvas.drawCircle(Offset(w * 0.50, h * 0.32), w * 0.16, fill);
        canvas.drawCircle(Offset(w * 0.50, h * 0.32), w * 0.16, stroke);
        final body = Path()
          ..moveTo(w * 0.18, h * 0.84)
          ..quadraticBezierTo(w * 0.18, h * 0.58, w * 0.50, h * 0.58)
          ..quadraticBezierTo(w * 0.82, h * 0.58, w * 0.82, h * 0.84)
          ..close();
        canvas.drawPath(body, fill);
        canvas.drawPath(body, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BottomNavIconPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.isSelected != isSelected;
}

class _BannerSlot {
  final int number;
  const _BannerSlot(this.number);
}

const _bannerSlots = [
  _BannerSlot(1),
  _BannerSlot(2),
  _BannerSlot(3),
];

class _PromoBannerData {
  final String contentKey;
  final String tag;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PromoBannerData({
    required this.contentKey,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _PromoCardAccentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p1 = Paint()
      ..color = const Color(0xFF0550A6).withValues(alpha: 0.08);
    final path1 = Path()
      ..moveTo(w * 0.72, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.62, h)
      ..close();
    canvas.drawPath(path1, p1);

    final p2 = Paint()
      ..color = const Color(0xFF033172).withValues(alpha: 0.06);
    final path2 = Path()
      ..moveTo(w * 0.84, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.74, h)
      ..close();
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
