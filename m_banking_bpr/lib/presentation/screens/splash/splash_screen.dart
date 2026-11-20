import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/security/security_hardening_service.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../auth/login_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String hasSeenOnboardingKey = 'has_seen_onboarding';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _canNavigate = false;
  bool _hasNavigated = false;
  bool _hasSeenOnboarding = false;
  bool _isCheckingMaintenance = false;
  bool _isConnectionDialogOpen = false;
  AuthState? _pendingState;
  RootInspectionResult? _rootResult;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();

    _initializeStartup();
  }

  Future<void> _initializeStartup() async {
    context.read<AuthCubit>().checkAuthStatus();

    try {
      final prefs = await SharedPreferences.getInstance();
      _hasSeenOnboarding = prefs.getBool(SplashScreen.hasSeenOnboardingKey) ?? false;
    } catch (_) {
      _hasSeenOnboarding = false;
    }

    try {
      final rootRes = await SecurityHardeningService.checkRootStatus();
      if (rootRes.isRooted) {
        _rootResult = rootRes;
      }
    } catch (_) {}

    await _connectAndProceed();
  }

  Future<void> _connectAndProceed() async {
    final results = await Future.wait([
      DynamicConfigService().syncStartup(),
      Future.delayed(const Duration(milliseconds: 1800), () => true),
    ]);

    if (!mounted) return;
    final connected = results[0];
    if (!connected) {
      _showConnectionErrorDialog();
      return;
    }

    setState(() => _canNavigate = true);
    final currentState = context.read<AuthCubit>().state;
    if (currentState is AuthAuthenticated ||
        currentState is AuthUnauthenticated ||
        currentState is AuthError) {
      _navigateToNextScreen(currentState);
    } else if (_pendingState != null) {
      _navigateToNextScreen(_pendingState!);
    } else {
      _navigateToNextScreen(AuthUnauthenticated());
    }
  }

  void _showConnectionErrorDialog() {
    if (!mounted || _isConnectionDialogOpen) return;
    _isConnectionDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE4E6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(0xFFE11D48),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Koneksi Bermasalah',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.titleDark,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Koneksi internet Anda terputus atau layanan sedang tidak dapat dihubungi. Periksa jaringan Anda dan silakan coba kembali.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    _isConnectionDialogOpen = false;
                    _connectAndProceed();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Coba Lagi',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retryMaintenanceCheck() async {
    setState(() => _isCheckingMaintenance = true);
    await DynamicConfigService().refreshFromServer();
    if (!mounted) return;
    setState(() => _isCheckingMaintenance = false);
    if (!DynamicConfigService().config.maintenanceMode && _canNavigate) {
      final currentState = context.read<AuthCubit>().state;
      _navigateToNextScreen(currentState);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _navigateToNextScreen(AuthState state) {
    if (!mounted || _hasNavigated) return;
    if (DynamicConfigService().config.maintenanceMode) {
      setState(() {});
      return;
    }
    _hasNavigated = true;

    final Widget destination;
    if (state is AuthAuthenticated) {
      destination = const HomeScreen();
    } else if (_hasSeenOnboarding) {
      destination = const LoginScreen();
    } else {
      destination = const OnboardingScreen();
    }

    final rootWarning = _rootResult;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (ctx, __, ___) {
          if (rootWarning != null && rootWarning.isRooted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) {
                SecurityHardeningService.showRootWarningDialog(ctx, rootWarning);
              }
            });
          }
          return destination;
        },
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.primaryNavy,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          _pendingState = state;
          if (_canNavigate) {
            _navigateToNextScreen(state);
          }
        },
        child: ListenableBuilder(
          listenable: DynamicConfigService(),
          builder: (context, _) {
            final config = DynamicConfigService().config;
            return Scaffold(
              backgroundColor: Colors.white,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const ContentImage(
                    'splash.background',
                    placeholder: ColoredBox(color: Colors.white),
                  ),

                  SafeArea(
                    child: Column(
                      children: [
                        const Spacer(flex: 3),

                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ContentImage(
                                  'app.logo',
                                  width: 220,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.92),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: AppColors.borderLight),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primaryNavy.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    AppContent.text('splash.tagline'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryNavy,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Spacer(flex: 5),

                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 140,
                                height: 3.5,
                                decoration: BoxDecoration(
                                  color: AppColors.borderLight.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const ClipRRect(
                                  borderRadius: BorderRadius.all(Radius.circular(4)),
                                  child: LinearProgressIndicator(
                                    backgroundColor: Colors.transparent,
                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.dmbGreen),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppContent.text('splash.loading_text'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF334155),
                                  letterSpacing: 0.2,
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(0, 1),
                                      blurRadius: 3,
                                      color: Colors.white.withOpacity(0.85),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Spacer(flex: 1),

                        Padding(
                          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
                          child: Column(
                            children: [
                              Text(
                                AppContent.text('splash.disclaimer'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.95),
                                  height: 1.35,
                                  letterSpacing: 0.15,
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(0, 1),
                                      blurRadius: 4,
                                      color: Colors.black.withOpacity(0.45),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${config.bankShortName} Mobile v1.0.0',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.85),
                                  letterSpacing: 0.5,
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(0, 1),
                                      blurRadius: 3,
                                      color: Colors.black.withOpacity(0.4),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (config.maintenanceMode)
                    _buildMaintenanceOverlay(config),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMaintenanceOverlay(DynamicAppConfig config) {
    final msg = config.maintenanceMessage.trim().isNotEmpty
        ? config.maintenanceMessage.trim()
        : 'Layanan sedang dalam pemeliharaan berkala untuk peningkatan kualitas layanan perbankan Anda.';
    return Container(
      color: AppColors.primaryDark.withOpacity(0.82),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.warningBorder, width: 1.5),
                ),
                child: const Icon(
                  Icons.engineering_rounded,
                  color: AppColors.warning,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pemeliharaan Layanan Terjadwal',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.titleDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingMaintenance ? null : _retryMaintenanceCheck,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isCheckingMaintenance
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    _isCheckingMaintenance ? 'Memeriksa Status...' : 'Coba Lagi',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
