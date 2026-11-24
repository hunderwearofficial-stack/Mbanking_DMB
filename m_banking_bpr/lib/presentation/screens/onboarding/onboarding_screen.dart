import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/content/app_content.dart';
import '../auth/terms_conditions_screen.dart';

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
          'fallbackAsset': 'assets/images/onboarding_slide1.jpg',
          'badge': 'LAYANAN DIGITAL TERPADU',
        },
        {
          'title': AppContent.text('onboarding.slide2_title'),
          'desc': AppContent.text('onboarding.slide2_desc'),
          'imageKey': 'onboarding.slide2_image',
          'fallbackAsset': 'assets/images/onboarding_slide2.jpg',
          'badge': 'KEAMANAN PERBANKAN BERLAPIS',
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

  void _navigateToTerms() {
    _autoSlideTimer?.cancel();
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
        systemNavigationBarColor: Color(0xFFF4F7FB),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        body: Column(
          children: [
            // Top Royal-Blue Showcase Header (matched to Splash Screen palette)
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF033172),
                      Color(0xFF0550A6),
                      Color(0xFF118CE0),
                    ],
                    stops: [0.0, 0.52, 1.0],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x28061B44),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ContentImage(
                              'app.logo',
                              height: 40,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              placeholder: RichText(
                                text: TextSpan(
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
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
                            TextButton(
                              onPressed: _navigateToTerms,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(color: Colors.white.withOpacity(0.24)),
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

                        const SizedBox(height: 16),

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
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.18),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF041028).withOpacity(0.35),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(23),
                                    child: ContentImage(
                                      slide['imageKey']!,
                                      asset: slide['fallbackAsset']!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
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
                              height: 6,
                              width: isActive ? 26 : 8,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFF00E5FF)
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
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFFE6EEF8)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF061B44).withOpacity(0.06),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _slides[_currentPage]['badge']!,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0B3A7D),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _slides[_currentPage]['title']!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 20.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0A1628),
                                height: 1.25,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _slides[_currentPage]['desc']!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF475569),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF033172), Color(0xFF0550A6), Color(0xFF118CE0)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0550A6).withOpacity(0.28),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: SizedBox(
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
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _currentPage < _slides.length - 1
                                      ? 'Lanjut'
                                      : AppContent.text('onboarding.button_text'),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
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
