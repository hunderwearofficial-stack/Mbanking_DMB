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
import '../../../data/repositories/auth_repository.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/smart_security_capsule.dart';
import '../account/account_info_screen.dart';
import '../auth/login_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../mutation/mutation_screen.dart';
import '../notification/notification_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/security_settings_screen.dart';
import 'widgets/quick_menu_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0;
  int _unreadNotifications = 0;

  Money? _cachedBalance;
  String? _cachedAccountNo;
  String? _cachedUserName;

  final PageController _promoPageController = PageController(viewportFraction: 0.88);
  int _currentPromoPage = 0;
  Timer? _promoTimer;

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;

  @override
  void initState() {
    super.initState();
    _startPromoTimer();
    context.read<AccountCubit>().loadDashboardData();
    _checkUnreadNotifications();

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
        setState(() => _currentNavIndex = 3);
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
            backgroundColor: const Color(0xFFF6F6F2),
            extendBody: true,
            body: IndexedStack(
              index: _currentNavIndex,
              children: [
                _buildHomeContent(),
                const MutationScreen(isTab: true),
                const NotificationScreen(isTab: true),
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

        return SafeArea(
          bottom: false,
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
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopHeader(userName, rawAccountNo),

                  _buildAnnouncementBanner(),

                  const SizedBox(height: 18),

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

                  const SizedBox(height: 22),

                  _buildPromoBanner(),

                  const SizedBox(height: 22),

                  const FigmaMenuGrid(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(String userName, String rawAccountNo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SmartSecurityCapsule(
              customerName: userName,
              accountNumber: rawAccountNo,
            ),

            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                );
              },
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.headset_mic_outlined,
                  color: Color(0xFF0A2A66),
                  size: 20,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        Text(
          AppContent.text('home.greeting_title'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          userName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: titleDark,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          AppContent.text('home.greeting_subtitle'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

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
            color: AppColors.successLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.successBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.dmbGreen.withOpacity(0.06),
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
                  color: AppColors.dmbGreen.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: AppColors.dmbGreen,
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
                    color: AppColors.textPrimary,
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A2A66), Color(0xFF0D3882)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A2A66).withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
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
                // Subtle concentric rings decoration on the right
                Positioned(
                  right: -45,
                  top: -35,
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 16,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -15,
                  top: -5,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.06),
                        width: 12,
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.credit_card_rounded,
                              color: Colors.white,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rekening Utama',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.78),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  accountNoFormatted,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canCopy)
                            Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: rawAccountNo));
                                  _showToast('Nomor rekening disalin: $rawAccountNo');
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  child: Text(
                                    'Salin',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0A2A66),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Saldo Tersedia',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.80),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  balance == null
                                      ? 'Saldo belum tersedia'
                                      : isBalanceVisible
                                          ? CurrencyFormatter.formatRupiah(balance)
                                          : 'Rp ••••••••',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: balance == null ? 15 : 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: const Color(0xFF4ADEA8),
                            borderRadius: BorderRadius.circular(22),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: onToggleVisibility,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isBalanceVisible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: const Color(0xFF064E3B),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isBalanceVisible ? 'Tutup' : 'Lihat',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF064E3B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
            cardBgColor: slot.cardBgColor,
            tagColor: slot.tagColor,
            onTap: () => _onBannerAction(AppContent.text('home.banner${slot.number}_action')),
          ),
    ];
    if (banners.isEmpty) return const SizedBox.shrink();
    if (_currentPromoPage >= banners.length) _currentPromoPage = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppContent.text('home.info_section_title'),
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            color: titleDark,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 132,
          child: PageView.builder(
            controller: _promoPageController,
            padEnds: false,
            itemCount: banners.length,
            onPageChanged: (index) {
              setState(() {
                _currentPromoPage = index;
              });
            },
            itemBuilder: (context, index) {
              final item = banners[index];
              final hasImage = AppContent.imageUrl(item.contentKey) != null;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: item.onTap,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: item.cardBgColor,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hasImage) ...[
                            ContentImage(
                              item.contentKey,
                              fit: BoxFit.cover,
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.15),
                                    Colors.black.withOpacity(0.70),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item.tag.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: item.tagColor,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item.title.trim().isNotEmpty)
                                      Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: hasImage ? Colors.white : titleDark,
                                          height: 1.25,
                                        ),
                                      ),
                                    if (item.subtitle.trim().isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        item.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: hasImage
                                              ? Colors.white.withOpacity(0.90)
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
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
            },
          ),
        ),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(banners.length, (index) {
            final isActive = _currentPromoPage == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.only(right: 5),
              width: isActive ? 20 : 6,
              height: 5,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF0F9D76) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0A2A66),
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A2A66).withOpacity(0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  icon: Icons.home_rounded,
                  label: 'Beranda',
                  isSelected: _currentNavIndex == 0,
                  onTap: () => setState(() => _currentNavIndex = 0),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  icon: Icons.history_rounded,
                  label: 'Riwayat',
                  isSelected: _currentNavIndex == 1,
                  onTap: () => setState(() => _currentNavIndex = 1),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifikasi',
                  isSelected: _currentNavIndex == 2,
                  showDot: _unreadNotifications > 0,
                  onTap: () {
                    setState(() => _currentNavIndex = 2);
                    _checkUnreadNotifications();
                  },
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Akun saya',
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
    required IconData icon,
    required String label,
    required bool isSelected,
    bool showDot = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? Colors.white.withOpacity(0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.72),
                  size: 21,
                ),
                if (showDot)
                  Positioned(
                    top: -2,
                    right: -3,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerSlot {
  final int number;
  final Color cardBgColor;
  final Color tagColor;
  const _BannerSlot(this.number, this.cardBgColor, this.tagColor);
}

const _bannerSlots = [
  _BannerSlot(1, Color(0xFFDDF7EC), Color(0xFF0F9D76)),
  _BannerSlot(2, Color(0xFFEAEFFE), Color(0xFF3730A3)),
  _BannerSlot(3, Color(0xFFE0F2FE), Color(0xFF0369A1)),
];

class _PromoBannerData {
  final String contentKey;
  final String tag;
  final String title;
  final String subtitle;
  final Color cardBgColor;
  final Color tagColor;
  final VoidCallback onTap;

  const _PromoBannerData({
    required this.contentKey,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.cardBgColor,
    required this.tagColor,
    required this.onTap,
  });
}
