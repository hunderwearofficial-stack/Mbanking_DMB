import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../auth/login_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _canNavigate = false;
  AuthState? _pendingState;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Entrance animation for logo and brand texts
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();

    // 2. Check auth status in background immediately so verification is ready
    context.read<AuthCubit>().checkAuthStatus();

    // 3. Full 10-second display time as requested
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
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
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _navigateToNextScreen(AuthState state) {
    if (!mounted) return;
    if (state is AuthAuthenticated) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A3B66),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          _pendingState = state;
          if (_canNavigate) {
            _navigateToNextScreen(state);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Official High-DPI DMB Mobile Artwork (Tugu Kujang + Gunung Salak + Waves)
              Image.asset(
                'assets/images/splash_artwork.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),

              // 2. Foreground Elements Layer
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 3),

                    // Official Logo & Brand Identity (Code-rendered with entrance animation)
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Official DMB Mobile Logo
                            Image.asset(
                              'assets/images/bank_logo.png',
                              width: 220,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 12),

                            // Official Brand Slogan Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.90),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0B356D).withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Sahabat Finansial Terpercaya Anda',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0B356D),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(flex: 5),

                    // Slim clean DMB Green progress indicator & status text
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 140,
                            height: 3.5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const ClipRRect(
                              borderRadius: BorderRadius.all(Radius.circular(4)),
                              child: LinearProgressIndicator(
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF16984B)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Memuat layanan perbankan...',
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

                    // Official Regulatory Disclaimer Text (OJK & LPS) + Version
                    Padding(
                      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
                      child: Column(
                        children: [
                          Text(
                            'PT BPR Dana Mandiri Bogor berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS).',
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
                            'DMB Mobile v1.0.0',
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
            ],
          ),
        ),
      ),
    );
  }
}
