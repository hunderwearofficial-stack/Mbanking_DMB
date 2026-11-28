import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/services/terms_consent_store.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
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
  bool _obscurePassword = true;
  bool _rememberMe = false; // opt-in: identifier is only kept on this device when the customer asks (audit MA-10)
  bool _lastLoginWasBiometric = false;
  BiometricCapability? _biometricCapability;

  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
  }

  Future<void> _loadSavedUsername() async {
    try {
      final storage = context.read<AuthCubit>().authRepository.secureStorage;
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberMePrefKey) ?? false;
      String? savedUser;
      if (remember) {
        savedUser = prefs.getString(_savedIdentifierPrefKey);
        if (savedUser == null || savedUser.isEmpty) {
          savedUser = await storage.getUsername() ?? await storage.getPhoneNumber();
        }
      }
      final bioCap = await BiometricAuthService.checkCapability();

      if (mounted) {
        setState(() {
          _rememberMe = remember;
          if (remember && savedUser != null && savedUser.isNotEmpty && _usernameController.text.isEmpty) {
            _usernameController.text = savedUser;
          }
          _biometricCapability = bioCap;
        });
      }
    } catch (_) {}
  }

  Future<void> _persistRememberMePreference(String identifier) async {
    try {
      final storage = context.read<AuthCubit>().authRepository.secureStorage;
      final prefs = await SharedPreferences.getInstance();
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
        _lastLoginWasBiometric = true;
        context.read<AuthCubit>().loginWithBiometric();
      }
    } else if (result.errorMessage != null) {
      _showWarning(result.errorMessage!);
    }
  }

  @override
  void dispose() {
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

    _lastLoginWasBiometric = false;
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
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AuthUiTokens.canvas,
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
              AppToast.showInfo(
                context,
                'Silakan baca dan setujui Syarat & Ketentuan yang berlaku terlebih dahulu.',
                title: 'Persetujuan S&K',
              );
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (termsCtx, __, ___) => TermsConditionsScreen(
                    onAccepted: () {
                      Navigator.of(termsCtx).pop();
                      if (!mounted) return;
                      if (_lastLoginWasBiometric) {
                        context.read<AuthCubit>().loginWithBiometric();
                      } else if (_usernameController.text.trim().isNotEmpty &&
                          _passwordController.text.trim().isNotEmpty) {
                        _onLogin();
                      }
                    },
                  ),
                  transitionsBuilder: (_, animation, __, child) =>
                      FadeTransition(opacity: animation, child: child),
                  transitionDuration: const Duration(milliseconds: 350),
                ),
              );
              return;
            }
            AppToast.showError(context, state.message, title: 'Gagal Masuk');
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;
          final announcement = AppContent.text('app.announcement').trim();

          return Scaffold(
            backgroundColor: AuthUiTokens.deepCobalt,
            body: Stack(
              children: [
                // Top Full-Bleed Navy Hero with Real Bank DMB Building on Right
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 315,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/home_header_landmark.jpg',
                        fit: BoxFit.cover,
                        alignment: Alignment.topRight,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AuthUiTokens.deepCobalt.withValues(alpha: 0.96),
                              AuthUiTokens.deepCobalt.withValues(alpha: 0.84),
                              AuthUiTokens.royalBlue.withValues(alpha: 0.35),
                            ],
                            stops: const [0.0, 0.48, 1.0],
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AuthUiTokens.deepCobalt.withValues(alpha: 0.72),
                              Colors.transparent,
                              AuthUiTokens.deepCobalt.withValues(alpha: 0.45),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Scrollable Body: Hero Content + White Bottom Sheet Form
                SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Top Brand Bar + Hero Headline over Real Bank DMB Building
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Image.asset(
                                            'assets/images/mydmb_logo_official.png',
                                            height: 44,
                                            fit: BoxFit.contain,
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.14),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.28),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.verified_user_outlined,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Aman & Terpercaya',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 28),

                                      Text(
                                        AppContent.text('login.title'),
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          height: 1.22,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        AppContent.text('login.subtitle'),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withValues(alpha: 0.88),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Clean White Bottom Sheet Form Card
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(28),
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          height: 76,
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _LoginBottomWavePainter(),
                                            ),
                                          ),
                                        ),

                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              if (announcement.isNotEmpty) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                                  margin: const EdgeInsets.only(bottom: 18),
                                                  decoration: BoxDecoration(
                                                    color: AuthUiTokens.softBlueBg,
                                                    borderRadius: BorderRadius.circular(14),
                                                    border: Border.all(
                                                      color: AuthUiTokens.softBlueBorder,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.campaign_rounded,
                                                        color: AuthUiTokens.royalBlue,
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          announcement,
                                                          style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: AuthUiTokens.titleDark,
                                                            height: 1.35,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],

                                              const Text(
                                                'No. HP atau Username',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AuthUiTokens.titleDark,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: AuthUiTokens.inputFill,
                                                  borderRadius: BorderRadius.circular(14),
                                                  border: Border.all(color: AuthUiTokens.inputBorder),
                                                ),
                                                child: TextField(
                                                  controller: _usernameController,
                                                  keyboardType: TextInputType.text,
                                                  autocorrect: false,
                                                  textInputAction: TextInputAction.next,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: AuthUiTokens.titleDark,
                                                  ),
                                                  decoration: const InputDecoration(
                                                    hintText: 'Contoh: 0812 3456 7890',
                                                    hintStyle: TextStyle(
                                                      color: Color(0xFF94A3B8),
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w400,
                                                    ),
                                                    prefixIcon: Icon(
                                                      Icons.person_outline_rounded,
                                                      color: AuthUiTokens.royalBlue,
                                                      size: 20,
                                                    ),
                                                    border: InputBorder.none,
                                                    enabledBorder: InputBorder.none,
                                                    focusedBorder: InputBorder.none,
                                                    contentPadding: EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 15,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              const SizedBox(height: 16),

                                              const Text(
                                                'Kata Sandi',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AuthUiTokens.titleDark,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: AuthUiTokens.inputFill,
                                                  borderRadius: BorderRadius.circular(14),
                                                  border: Border.all(color: AuthUiTokens.inputBorder),
                                                ),
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
                                                    color: AuthUiTokens.titleDark,
                                                  ),
                                                  decoration: InputDecoration(
                                                    hintText: 'Masukkan kata sandi',
                                                    hintStyle: const TextStyle(
                                                      color: Color(0xFF94A3B8),
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w400,
                                                    ),
                                                    prefixIcon: const Icon(
                                                      Icons.lock_outline_rounded,
                                                      color: AuthUiTokens.royalBlue,
                                                      size: 20,
                                                    ),
                                                    suffixIcon: IconButton(
                                                      icon: Icon(
                                                        _obscurePassword
                                                            ? Icons.visibility_off_outlined
                                                            : Icons.visibility_outlined,
                                                        color: AuthUiTokens.textMuted,
                                                        size: 20,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _obscurePassword = !_obscurePassword;
                                                        });
                                                      },
                                                    ),
                                                    border: InputBorder.none,
                                                    enabledBorder: InputBorder.none,
                                                    focusedBorder: InputBorder.none,
                                                    contentPadding: const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 15,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              const SizedBox(height: 14),

                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
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
                                                                color: _rememberMe
                                                                    ? AuthUiTokens.royalBlue
                                                                    : const Color(0xFF94A3B8),
                                                                width: 1.5,
                                                              ),
                                                              color: _rememberMe
                                                                  ? AuthUiTokens.royalBlue
                                                                  : Colors.transparent,
                                                            ),
                                                            child: _rememberMe
                                                                ? const Icon(
                                                                    Icons.check,
                                                                    size: 11,
                                                                    color: Colors.white,
                                                                  )
                                                                : null,
                                                          ),
                                                          const SizedBox(width: 8),
                                                          const Text(
                                                            'Ingat Saya',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight: FontWeight.w500,
                                                              color: AppColors.textSecondary,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () {
                                                      Navigator.of(context).push(
                                                        MaterialPageRoute(
                                                          builder: (_) => const ForgotPasswordScreen(),
                                                        ),
                                                      );
                                                    },
                                                    borderRadius: BorderRadius.circular(6),
                                                    child: const Padding(
                                                      padding: EdgeInsets.symmetric(
                                                        vertical: 4,
                                                        horizontal: 2,
                                                      ),
                                                      child: Text(
                                                        'Lupa Kata Sandi?',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w700,
                                                          color: AuthUiTokens.deepCobalt,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),

                                              const SizedBox(height: 22),

                                              SizedBox(
                                                height: 52,
                                                child: ElevatedButton(
                                                  onPressed: isLoading ? null : _onLogin,
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: AuthUiTokens.deepCobalt,
                                                    disabledBackgroundColor: AuthUiTokens.deepCobalt,
                                                    foregroundColor: Colors.white,
                                                    elevation: 0,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(26),
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
                                                      : const Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Text(
                                                              'Masuk',
                                                              style: TextStyle(
                                                                fontSize: 15.5,
                                                                fontWeight: FontWeight.w700,
                                                                letterSpacing: 0.2,
                                                              ),
                                                            ),
                                                            SizedBox(width: 6),
                                                            Icon(
                                                              Icons.chevron_right_rounded,
                                                              size: 20,
                                                            ),
                                                          ],
                                                        ),
                                                ),
                                              ),

                                              if (showBiometricButton) ...[
                                                const SizedBox(height: 12),
                                                SizedBox(
                                                  height: 50,
                                                  child: OutlinedButton.icon(
                                                    onPressed: isLoading ? null : _onBiometricLogin,
                                                    icon: const Icon(
                                                      Icons.fingerprint_rounded,
                                                      size: 22,
                                                      color: AuthUiTokens.royalBlue,
                                                    ),
                                                    label: const Text(
                                                      'Masuk dengan Biometrik',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                        color: AuthUiTokens.deepCobalt,
                                                      ),
                                                    ),
                                                    style: OutlinedButton.styleFrom(
                                                      backgroundColor: Colors.white,
                                                      side: const BorderSide(
                                                        color: AuthUiTokens.inputBorder,
                                                        width: 1.2,
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(25),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],

                                              const SizedBox(height: 22),

                                              Row(
                                                children: [
                                                  const Expanded(
                                                    child: Divider(
                                                      color: AuthUiTokens.inputBorder,
                                                      thickness: 1,
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                                    child: InkWell(
                                                      onTap: () {
                                                        if (!TermsConsentStore.instance.hasAccepted) {
                                                          Navigator.of(context).push(
                                                            MaterialPageRoute(
                                                              builder: (termsCtx) => TermsConditionsScreen(
                                                                onAccepted: () {
                                                                  Navigator.of(termsCtx).pushReplacement(
                                                                    MaterialPageRoute(
                                                                      builder: (_) => const ActivationScreen(),
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          );
                                                          return;
                                                        }
                                                        Navigator.of(context).push(
                                                          MaterialPageRoute(
                                                            builder: (_) => const ActivationScreen(),
                                                          ),
                                                        );
                                                      },
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: const Padding(
                                                        padding: EdgeInsets.symmetric(
                                                          vertical: 4,
                                                          horizontal: 4,
                                                        ),
                                                        child: Text(
                                                          'Aktivasi / Daftar',
                                                          style: TextStyle(
                                                            fontSize: 13.5,
                                                            fontWeight: FontWeight.w700,
                                                            color: AuthUiTokens.deepCobalt,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const Expanded(
                                                    child: Divider(
                                                      color: AuthUiTokens.inputBorder,
                                                      thickness: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),

                                              const SizedBox(height: 18),

                                              Text(
                                                AppContent.text('app.footer'),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                  color: AuthUiTokens.textMuted,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
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
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LoginBottomWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final wave1 = Paint()
      ..color = AuthUiTokens.azureBlue.withValues(alpha: 0.08);
    final p1 = Path()
      ..moveTo(0, h * 0.55)
      ..quadraticBezierTo(w * 0.28, h * 0.15, w * 0.62, h * 0.55)
      ..quadraticBezierTo(w * 0.84, h * 0.80, w, h * 0.35)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p1, wave1);

    final wave2 = Paint()
      ..color = AuthUiTokens.deepCobalt.withValues(alpha: 0.06);
    final p2 = Path()
      ..moveTo(0, h * 0.75)
      ..quadraticBezierTo(w * 0.45, h * 0.42, w, h * 0.72)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p2, wave2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
