import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../auth/terms_conditions_screen.dart';
import '../splash/splash_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _autoSlideTimer;
  bool _userInteracted = false;

  List<Map<String, String>> get _slides => [
        {
          'title': AppContent.text('onboarding.slide1_title'),
          'desc': AppContent.text('onboarding.slide1_desc'),
          'imageKey': 'onboarding.slide1_image',
        },
        {
          'title': AppContent.text('onboarding.slide2_title'),
          'desc': AppContent.text('onboarding.slide2_desc'),
          'imageKey': 'onboarding.slide2_image',
        },
      ];

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    if (_userInteracted) return;
    _autoSlideTimer = Timer.periodic(const Duration(milliseconds: 4500), (timer) {
      if (!mounted || _userInteracted) {
        timer.cancel();
        return;
      }
      if (_currentPage < _slides.length - 1) {
        _pageController.animateToPage(
          _currentPage + 1,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOutCubic,
        );
      } else {
        timer.cancel();
      }
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  Future<void> _markOnboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SplashScreen.hasSeenOnboardingKey, true);
    } catch (_) {}
  }

  Future<void> _navigateToTerms() async {
    _autoSlideTimer?.cancel();
    await _markOnboardingSeen();
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const TermsConditionsScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        body: Column(
          children: [
            // Top Navy Showcase Header
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A2A66), Color(0xFF0D3882)],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const ContentImage(
                              'app.logo',
                              height: 44,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                            ),
                            TextButton(
                              onPressed: _navigateToTerms,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(color: Colors.white.withOpacity(0.25)),
                                ),
                                backgroundColor: Colors.white.withOpacity(0.12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Lewati',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        Expanded(
                          child: Listener(
                            onPointerDown: (_) {
                              _userInteracted = true;
                              _autoSlideTimer?.cancel();
                            },
                            child: PageView.builder(
                              controller: _pageController,
                              onPageChanged: _onPageChanged,
                              itemCount: _slides.length,
                              physics: const BouncingScrollPhysics(),
                              itemBuilder: (context, index) {
                                final slide = _slides[index];
                                return Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: double.infinity,
                                      child: ContentImage(
                                        slide['imageKey']!,
                                        fit: BoxFit.cover,
                                        placeholder: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(22),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.12),
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(22),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF34D399).withOpacity(0.16),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  index == 0
                                                      ? Icons.account_balance_wallet_rounded
                                                      : Icons.verified_user_rounded,
                                                  color: const Color(0xFF34D399),
                                                  size: 54,
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              Text(
                                                index == 0
                                                    ? 'SIMPANAN & MUTASI REAL-TIME'
                                                    : 'KEAMANAN PERBANKAN BERLAPIS',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF34D399),
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_slides.length, (index) {
                            final isActive = index == _currentPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 5,
                              width: isActive ? 24 : 7,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFF34D399)
                                    : Colors.white.withOpacity(0.32),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom White Content Card
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
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
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          key: ValueKey(_currentPage),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _slides[_currentPage]['title']!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: AppColors.titleDark,
                                height: 1.25,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _slides[_currentPage]['desc']!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textMuted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_currentPage < _slides.length - 1) {
                              _userInteracted = true;
                              _autoSlideTimer?.cancel();
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _navigateToTerms();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A2A66),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentPage < _slides.length - 1
                                    ? 'Lanjut'
                                    : AppContent.text('onboarding.button_text'),
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
