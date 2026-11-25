import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/content/app_content.dart';
import '../../../core/services/terms_consent_store.dart';
import '../auth/login_screen.dart';
import '../auth/terms_conditions_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  PageRoute<void> _slideRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }

  void _handleLogin(BuildContext context) {
    if (TermsConsentStore.instance.hasAccepted) {
      Navigator.of(context).push(_slideRoute(const LoginScreen()));
      return;
    }
    Navigator.of(context).push(_slideRoute(const TermsConditionsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final title = AppContent.text('onboarding.title').trim().isNotEmpty
        ? AppContent.text('onboarding.title').trim()
        : 'Solusi Finansial Terpercaya untuk Keluarga & UMKM';
    final subtitle = AppContent.text('onboarding.subtitle').trim().isNotEmpty
        ? AppContent.text('onboarding.subtitle').trim()
        : 'Pantau saldo tabungan, mutasi rekening, deposito, dan pinjaman Anda secara aman dan real-time.';
    final loginBtnText =
        AppContent.text('onboarding.button_text').trim().isNotEmpty
            ? AppContent.text('onboarding.button_text').trim()
            : 'Masuk Sekarang';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF04122E),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF04122E),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Full-bleed hero photo from server (with deep-navy gradient fallback)
            ContentImage(
              'onboarding.background',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.2),
              placeholder: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0B3A7D), Color(0xFF04122E)],
                  ),
                ),
              ),
            ),

            // Top vignette for status bar & brand mark legibility
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 150,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF04122E).withOpacity(0.58),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom gradient scrim for headline, subtitle & CTA buttons
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x3304122E),
                        Color(0xD804122E),
                        Color(0xFF04122E),
                      ],
                      stops: [0.36, 0.52, 0.72, 0.90],
                    ),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top-left brand mark from Backoffice Pengaturan (`app.logo`)
                    ContentImage(
                      'app.logo',
                      height: 44,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      placeholder: RichText(
                        text: TextSpan(
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 1),
                                blurRadius: 8,
                                color: Colors.black.withOpacity(0.45),
                              ),
                            ],
                          ),
                          children: const [
                            TextSpan(
                              text: 'my',
                              style: TextStyle(color: Color(0xFF00E5FF)),
                            ),
                            TextSpan(
                              text: 'DMB',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Headline & subtitle
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.24,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.86),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Primary CTA: Masuk Sekarang (Livin'-style vibrant blue pill)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => _handleLogin(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0077FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text(
                          loginBtnText,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
