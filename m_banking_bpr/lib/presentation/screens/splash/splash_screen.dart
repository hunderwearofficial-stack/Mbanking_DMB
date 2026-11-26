import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/security/security_hardening_service.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../core/services/terms_consent_store.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_loading_overlay.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String hasSeenOnboardingKey = 'has_seen_onboarding';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _canNavigate = false;
  bool _hasNavigated = false;
  bool _isCheckingMaintenance = false;
  bool _isConnectionFailed = false;
  bool _isRetryingConnection = false;
  bool _isAutoProbing = false;
  Timer? _autoRetryTimer;
  AuthState? _pendingState;
  RootInspectionResult? _rootResult;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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
      await TermsConsentStore.instance.restore();
    } catch (_) {}

    try {
      final rootRes = await SecurityHardeningService.checkRootStatus();
      if (rootRes.isRooted) {
        _rootResult = rootRes;
      }
    } catch (_) {}

    await _connectAndProceed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _isConnectionFailed &&
        !_hasNavigated) {
      _tryAutoReconnect();
    }
  }

  void _startAutoReconnectWatcher() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_isConnectionFailed || _hasNavigated) {
        _stopAutoReconnectWatcher();
        return;
      }
      _tryAutoReconnect();
    });
  }

  void _stopAutoReconnectWatcher() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
  }

  Future<void> _tryAutoReconnect() async {
    if (_isAutoProbing || _isRetryingConnection || _hasNavigated) return;
    _isAutoProbing = true;
    try {
      final connected = await DynamicConfigService().syncStartup();
      if (!mounted || _hasNavigated) return;
      if (connected) {
        _stopAutoReconnectWatcher();
        _finishConnectionSuccess();
      }
    } finally {
      _isAutoProbing = false;
    }
  }

  void _finishConnectionSuccess() {
    if (!mounted || _hasNavigated) return;
    setState(() {
      _isConnectionFailed = false;
      _isRetryingConnection = false;
      _canNavigate = true;
    });
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

  Future<void> _connectAndProceed({bool waitMinDuration = true}) async {
    final bool connected;
    if (waitMinDuration) {
      final results = await Future.wait([
        DynamicConfigService().syncStartup(),
        Future.delayed(const Duration(seconds: 10), () => true),
      ]);
      connected = results[0];
    } else {
      connected = await DynamicConfigService().syncStartup();
    }

    if (!mounted) return;
    if (!connected) {
      setState(() {
        _isConnectionFailed = true;
        _isRetryingConnection = false;
      });
      _startAutoReconnectWatcher();
      return;
    }

    _stopAutoReconnectWatcher();
    _finishConnectionSuccess();
  }

  void _retryConnection() {
    if (_isRetryingConnection) return;
    setState(() => _isRetryingConnection = true);
    _connectAndProceed(waitMinDuration: false);
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
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoReconnectWatcher();
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

    final Widget destination = state is AuthAuthenticated
        ? const HomeScreen()
        : const OnboardingScreen();

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
    return ListenableBuilder(
      listenable: DynamicConfigService(),
      builder: (context, _) {
        final config = DynamicConfigService().config;
        const Color defaultBg = Color(0xFF091324);
        const bool isLightBg = false;
        final Color centerGlow =
            Color.lerp(defaultBg, const Color(0xFF1E3A5F), 0.35)!;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isLightBg ? Brightness.dark : Brightness.light,
            statusBarBrightness:
                isLightBg ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: defaultBg,
            systemNavigationBarIconBrightness:
                isLightBg ? Brightness.dark : Brightness.light,
          ),
          child: BlocListener<AuthCubit, AuthState>(
            listener: (context, state) {
              _pendingState = state;
              if (_canNavigate) {
                _navigateToNextScreen(state);
              }
            },
            child: Scaffold(
              backgroundColor: defaultBg,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: isLightBg
                          ? RadialGradient(
                              center: const Alignment(0, -0.35),
                              radius: 1.05,
                              colors: [centerGlow, defaultBg],
                            )
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                defaultBg,
                                Color.lerp(defaultBg, const Color(0xFF0B3A7D), 0.72)!,
                                Color.lerp(defaultBg, const Color(0xFF196BB8), 0.85)!,
                              ],
                              stops: const [0.0, 0.52, 1.0],
                            ),
                    ),
                  ),

                  // Full-bleed splash background bundled directly in the app
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Image.asset(
                        'assets/images/splash_building.jpg',
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),

                  SafeArea(
                    child: Column(
                      children: [
                        const Spacer(flex: 2),

                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: _SplashBrandMark(
                              bankShortName: config.bankShortName,
                              tagline: AppContent.text('splash.tagline'),
                              isLightBg: isLightBg,
                            ),
                          ),
                        ),

                        const Spacer(flex: 6),

                        Padding(
                          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 10),
                          child: Text(
                            AppContent.text('splash.disclaimer'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.92),
                              height: 1.35,
                              shadows: [
                                Shadow(
                                  offset: const Offset(0, 1),
                                  blurRadius: 6,
                                  color: Colors.black.withOpacity(0.55),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_isConnectionFailed)
                    AppConnectionErrorView(
                      onRetry: _retryConnection,
                      isRetrying: _isRetryingConnection,
                      backgroundColor: defaultBg,
                    )
                  else if (config.maintenanceMode)
                    _buildMaintenanceOverlay(config),
                ],
              ),
            ),
          ),
        );
      },
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

class _SplashBrandMark extends StatefulWidget {
  final String bankShortName;
  final String tagline;
  final bool isLightBg;

  const _SplashBrandMark({
    required this.bankShortName,
    required this.tagline,
    required this.isLightBg,
  });

  @override
  State<_SplashBrandMark> createState() => _SplashBrandMarkState();
}

class _SplashBrandMarkState extends State<_SplashBrandMark>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _pulseController;

  late final Animation<double> _emblemScale;
  late final Animation<double> _emblemFade;
  late final Animation<double> _signalsProgress;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _emblemScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.44, curve: Curves.easeOutBack),
      ),
    );
    _emblemFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.0, 0.30, curve: Curves.easeOut),
    );
    _signalsProgress = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.22, 0.62, curve: Curves.easeOutCubic),
    );

    _titleFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.38, 0.76, curve: Curves.easeOutCubic),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.38, 0.76, curve: Curves.easeOutCubic),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.62, 1.0, curve: Curves.easeOutCubic),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.62, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var shortName = widget.bankShortName
        .replaceAll(RegExp(r'\b(pt|bpr|bank)\b', caseSensitive: false), '')
        .trim();
    if (shortName.toLowerCase().startsWith('my') && shortName.length > 2) {
      shortName = shortName.substring(2).trim();
    }
    if (shortName.isEmpty) {
      shortName = 'DMB';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _emblemFade,
          child: ScaleTransition(
            scale: _emblemScale,
            child: SizedBox(
              width: 160,
              height: 160,
              child: AnimatedBuilder(
                animation: Listenable.merge([_signalsProgress, _pulseController]),
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size.square(160),
                    painter: _MyDmbEmblemPainter(
                      signalReveal: _signalsProgress.value,
                      pulse: _pulseController.value,
                      isLightBg: widget.isLightBg,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FadeTransition(
          opacity: _titleFade,
          child: SlideTransition(
            position: _titleSlide,
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
                children: [
                  const TextSpan(
                    text: 'my',
                    style: TextStyle(color: Color(0xFF57DDD3)),
                  ),
                  TextSpan(
                    text: shortName,
                    style: TextStyle(
                      color: widget.isLightBg
                          ? const Color(0xFF0A1628)
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.tagline.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          FadeTransition(
            opacity: _taglineFade,
            child: SlideTransition(
              position: _taglineSlide,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Text(
                  widget.tagline,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    letterSpacing: 0.15,
                    color: widget.isLightBg
                        ? AppColors.titleDark.withOpacity(0.88)
                        : Colors.white.withOpacity(0.92),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Clean vector emblem matching the official myDMB logo geometry:
/// cyan ring, white cradling U-arc, cyan-blue bottom arch, and 3 Wi-Fi signal arcs.
class _MyDmbEmblemPainter extends CustomPainter {
  final double signalReveal;
  final double pulse;
  final bool isLightBg;

  _MyDmbEmblemPainter({
    required this.signalReveal,
    required this.pulse,
    required this.isLightBg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = math.min(size.width, size.height) / 245.0;
    canvas.save();
    canvas.scale(scale, scale);
    canvas.translate(112, 128);
    // Slight counter-clockwise tilt matching the official myDMB emblem.
    canvas.rotate(-0.18);

    final Shader ringShader = ui.Gradient.linear(
      const Offset(-24, -32),
      const Offset(24, 16),
      const [Color(0xFF57DDD3), Color(0xFF2EA2CE), Color(0xFF1A4B96)],
      const [0.0, 0.55, 1.0],
    );

    final Shader bottomArchShader = ui.Gradient.linear(
      const Offset(-48, 70),
      const Offset(48, 92),
      const [Color(0xFF57DDD3), Color(0xFF2EA2CE), Color(0xFF1A4B96)],
      const [0.0, 0.5, 1.0],
    );

    final Shader signalShader = ui.Gradient.linear(
      const Offset(0, -82),
      const Offset(82, 0),
      const [Color(0xFF57DDD3), Color(0xFF2EA2CE), Color(0xFF1A4B96)],
      const [0.0, 0.55, 1.0],
    );

    // 1. White cradling U-arc (flat butt ends matching official emblem)
    if (isLightBg) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(0, -4), radius: 46),
        math.pi * 0.04,
        math.pi * 0.92,
        false,
        Paint()
          ..color = const Color(0x220F172A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 21
          ..strokeCap = StrokeCap.butt,
      );
    }
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(0, -4), radius: 46),
      math.pi * 0.04,
      math.pi * 0.92,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.butt,
    );

    // 2. Cyan-to-blue downward arch below the U-arc (#57DDD3 -> #1A4B96)
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(0, 108), radius: 46),
      -math.pi * 0.92,
      math.pi * 0.84,
      false,
      Paint()
        ..shader = bottomArchShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.butt,
    );

    // 3. Cyan-to-blue center ring
    canvas.drawCircle(
      const Offset(0, -8),
      19,
      Paint()
        ..shader = ringShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13,
    );

    // 4. 3 Wi-Fi signal arcs radiating up-right
    canvas.save();
    canvas.translate(6, -12);
    const arcs = [
      (r: 36.0, delay: 0.0),
      (r: 52.0, delay: 0.18),
      (r: 68.0, delay: 0.36),
    ];
    for (final arc in arcs) {
      final reveal = ((signalReveal - arc.delay) / 0.45).clamp(0.0, 1.0);
      if (reveal <= 0) continue;
      final wave = 0.58 +
          0.42 * math.sin(((pulse - arc.delay) * math.pi * 2)).clamp(0.0, 1.0);
      final alpha = (reveal * wave).clamp(0.28, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: arc.r),
        -math.pi * 0.45,
        math.pi * 0.44,
        false,
        Paint()
          ..shader = signalShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9.0
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(alpha),
      );
    }
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MyDmbEmblemPainter oldDelegate) {
    return oldDelegate.signalReveal != signalReveal ||
        oldDelegate.pulse != pulse ||
        oldDelegate.isLightBg != isLightBg;
  }
}
