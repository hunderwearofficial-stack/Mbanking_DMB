import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/smart_security_capsule.dart';
import '../home/home_screen.dart';
import 'activation_screen.dart';
import 'forgot_password_screen.dart';
import 'terms_conditions_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _rememberMePrefKey = 'dmb_remember_me';
  static const String _savedIdentifierPrefKey = 'dmb_saved_login_identifier';

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final PageController _heroPageController = PageController();
  Timer? _heroTimer;
  int _heroSlideIndex = 0;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isBiometricEnabled = false;
  BiometricCapability? _biometricCapability;

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderColor = AppColors.borderLight;

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
    _startHeroAutoSlide();
  }

  void _startHeroAutoSlide() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_heroPageController.hasClients) return;
      final next = (_heroSlideIndex + 1) % 3;
      _heroPageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _loadSavedUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberMePrefKey) ?? true;
      final storage = context.read<AuthCubit>().authRepository.secureStorage;
      String? savedUser;
      if (remember) {
        savedUser = prefs.getString(_savedIdentifierPrefKey);
        if (savedUser == null || savedUser.isEmpty) {
          savedUser = await storage.getUsername() ?? await storage.getPhoneNumber();
        }
      }
      final isBio = await storage.isBiometricEnabled();
      final bioCap = await BiometricAuthService.checkCapability();

      if (mounted) {
        setState(() {
          _rememberMe = remember;
          if (remember && savedUser != null && savedUser.isNotEmpty && _usernameController.text.isEmpty) {
            _usernameController.text = savedUser;
          }
          _isBiometricEnabled = isBio;
          _biometricCapability = bioCap;
        });
      }
    } catch (_) {}
  }

  Future<void> _persistRememberMePreference(String identifier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storage = context.read<AuthCubit>().authRepository.secureStorage;
      await prefs.setBool(_rememberMePrefKey, _rememberMe);
      if (_rememberMe) {
        await prefs.setString(_savedIdentifierPrefKey, identifier);
        await storage.saveUsername(identifier);
      } else {
        await prefs.remove(_savedIdentifierPrefKey);
        await storage.clearSavedLoginIdentifier();
      }
    } catch (_) {}
  }

  Future<void> _onToggleRememberMe() async {
    final nextVal = !_rememberMe;
    setState(() => _rememberMe = nextVal);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMePrefKey, nextVal);
      if (!nextVal) {
        await prefs.remove(_savedIdentifierPrefKey);
        if (mounted) {
          await context.read<AuthCubit>().authRepository.secureStorage.clearSavedLoginIdentifier();
        }
      }
    } catch (_) {}
  }

  Future<void> _onBiometricLogin() async {
    final storage = context.read<AuthCubit>().authRepository.secureStorage;
    final isBio = await storage.isBiometricEnabled();

    if (!isBio) {
      _showWarning(
        'Login Biometrik belum diaktifkan. Silakan login dengan password terlebih dahulu, lalu aktifkan di menu Profil > Pengaturan Keamanan.',
      );
      return;
    }

    final result = await BiometricAuthService.authenticate(
      reason: 'Pindai sidik jari atau Face ID Anda untuk masuk ke Mobile DMB',
    );

    if (result.success) {
      if (mounted) {
        context.read<AuthCubit>().loginWithBiometric();
      }
    } else if (result.errorMessage != null) {
      _showWarning(result.errorMessage!);
    }
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroPageController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      _showWarning('Username / ID Pengguna wajib diisi');
      return;
    }

    if (password.isEmpty) {
      _showWarning('Kata sandi / Password wajib diisi');
      return;
    }

    _persistRememberMePreference(username);

    context.read<AuthCubit>().login(
          identifier: username,
          password: password,
        );
  }

  void _showWarning(String msg) {
    AppToast.showWarning(context, msg, title: 'Validasi Login');
  }


  @override
  Widget build(BuildContext context) {
    final showBiometricButton = _biometricCapability?.canAuthenticate ?? false;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const HomeScreen(),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 350),
              ),
            );
          } else if (state is AuthError) {
            if (state.requiresTermsConsent) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const TermsConditionsScreen(),
                  transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
                  transitionDuration: const Duration(milliseconds: 350),
                ),
              );
            }
            AppToast.showError(context, state.message, title: 'Gagal Masuk');
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;
          final welcomeTitle = AppContent.text('login.title');
          final welcomeSubtitle = AppContent.text('login.subtitle');
          final announcement = AppContent.text('app.announcement').trim();
          final hasCustomHeroBg = AppContent.imageUrl('login.background') != null;
          final heroSlides = [
            (
              badge: AppContent.text('login.hero_slide1_badge'),
              title: AppContent.text('login.hero_slide1_title'),
            ),
            (
              badge: AppContent.text('login.hero_slide2_badge'),
              title: AppContent.text('login.hero_slide2_title'),
            ),
            (
              badge: AppContent.text('login.hero_slide3_badge'),
              title: AppContent.text('login.hero_slide3_title'),
            ),
          ];

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Color(0xFFF6F6F2),
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            child: Scaffold(
              backgroundColor: const Color(0xFFF6F6F2),
              body: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Hero Banner Card
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0A2A66), Color(0xFF0D3882)],
                        ),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                        child: Stack(
                          children: [
                            if (hasCustomHeroBg)
                              const Positioned.fill(
                                child: Opacity(
                                  opacity: 0.28,
                                  child: ContentImage(
                                    'login.background',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            SafeArea(
                              bottom: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const SmartSecurityCapsule(),
                                        const Padding(
                                          padding: EdgeInsets.only(right: 12),
                                          child: ContentImage(
                                            'app.logo',
                                            height: 54,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 26),
                                    SizedBox(
                                      height: 92,
                                      child: PageView.builder(
                                        controller: _heroPageController,
                                        itemCount: heroSlides.length,
                                        onPageChanged: (idx) {
                                          if (mounted) {
                                            setState(() => _heroSlideIndex = idx);
                                          }
                                        },
                                        itemBuilder: (_, idx) {
                                          final slide = heroSlides[idx];
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text(
                                                slide.badge.toUpperCase(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF34D399),
                                                  letterSpacing: 0.9,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                slide.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                  height: 1.22,
                                                  letterSpacing: -0.3,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: List.generate(heroSlides.length, (i) {
                                        final active = i == _heroSlideIndex;
                                        return AnimatedContainer(
                                          duration: const Duration(milliseconds: 240),
                                          margin: const EdgeInsets.only(right: 6),
                                          height: 5,
                                          width: active ? 20 : 6,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? const Color(0xFF34D399)
                                                : Colors.white.withOpacity(0.35),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (announcement.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.successBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.campaign_rounded, color: dmbGreen, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  announcement,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // White Login Card
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              welcomeTitle,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: titleDark,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              welcomeSubtitle,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                                color: textMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),

                            const Text(
                              'No. HP atau Username',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: TextField(
                                controller: _usernameController,
                                keyboardType: TextInputType.text,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Contoh: 0812 3456 7890',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            const Text(
                              'Password',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.only(right: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) {
                                        if (!isLoading) _onLogin();
                                      },
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'Masukkan kata sandi',
                                        hintStyle: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: textMuted,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            InkWell(
                              onTap: _onToggleRememberMe,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _rememberMe ? dmbGreen : const Color(0xFF94A3B8),
                                          width: 1.5,
                                        ),
                                        color: _rememberMe ? dmbGreen : Colors.transparent,
                                      ),
                                      child: _rememberMe
                                          ? const Icon(Icons.check, size: 11, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Ingat Saya',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: isLoading ? null : _onLogin,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0A2A66),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.2,
                                              ),
                                            )
                                          : const Text(
                                              'Masuk',
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                if (showBiometricButton) ...[
                                  const SizedBox(width: 10),
                                  Container(
                                    height: 50,
                                    width: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: _onBiometricLogin,
                                        child: const Center(
                                          child: Icon(
                                            Icons.fingerprint_rounded,
                                            color: Color(0xFF0F9D76),
                                            size: 26,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 18),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                    child: Text(
                                      'Lupa password?',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0A2A66),
                                      ),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const ActivationScreen()),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                    child: Text(
                                      'Daftar',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0A2A66),
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

                    const SizedBox(height: 22),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        AppContent.text('login.footer'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
