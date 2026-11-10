import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // 2 Creative Onboarding Slides with DMB Corporate Copywriting
  final List<Map<String, String>> _slides = [
    {
      'title': 'Jadi bestie di dunia finansial anak dengan DMB Mobile',
      'desc':
          'Dari uang jajan sampai target impian anak, semua bisa didampingi bersama orang tua secara transparan dan mudah.',
      'image': 'assets/images/onboarding_slide_1.png',
    },
    {
      'title': 'Wujudkan masa depan keluarga dengan tabungan cerdas',
      'desc':
          'Bebas biaya transfer, bunga deposito menguntungkan, dan proteksi transaksi berlapis dalam genggaman Anda.',
      'image': 'assets/images/onboarding_slide_2.png',
    },
  ];

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(milliseconds: 4500), (timer) {
      if (!mounted) return;
      final nextPage = (_currentPage + 1) % _slides.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
    // Restart auto slide timer after user manual swipe
    _startAutoSlide();
  }

  void _navigateToTerms() {
    _autoSlideTimer?.cancel();
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
    ).then((_) {
      // Resume auto slide if user returns
      if (mounted) _startAutoSlide();
    });
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
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Pure Native Vector Background Wave Art (No Background Image!)
            CustomPaint(
              size: Size.infinite,
              painter: OnboardingVectorBackgroundPainter(),
            ),

            // 2. Foreground Content (Header, Animated Carousel, Button)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar: Clean DMB Mobile Official Logo
                    Image.asset(
                      'assets/images/bank_logo.png',
                      height: 38,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                    ),

                    const SizedBox(height: 16),

                    // Segmented Progress Indicator Bar (Syncs with Active Slide)
                    Row(
                      children: List.generate(_slides.length, (index) {
                        final isActive = index == _currentPage;
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: EdgeInsets.only(right: index < _slides.length - 1 ? 8 : 0),
                            height: 4,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF16984B) // Active DMB Green
                                  : const Color(0xFFE2E8F0), // Inactive Grey
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF16984B).withOpacity(0.35),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 12),

                    // Swipeable Carousel PageView
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: _slides.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final slide = _slides[index];

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),

                              // Headline Title
                              Text(
                                slide['title']!,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A), // Dark Navy
                                  height: 1.25,
                                  letterSpacing: -0.4,
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Subtitle Body Description
                              Text(
                                slide['desc']!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF64748B),
                                  height: 1.45,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Center 3D Illustration Card
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0F172A).withOpacity(0.08),
                                          blurRadius: 24,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 10,
                                        child: Image.asset(
                                          slide['image']!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: const Color(0xFFF1F5F9),
                                            child: const Center(
                                              child: Icon(Icons.image_outlined,
                                                  color: Color(0xFF94A3B8), size: 40),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),
                            ],
                          );
                        },
                      ),
                    ),

                    // Bottom Primary Action Button: "Mulai Sekarang →" (Navigates to Terms & Conditions Screen)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _navigateToTerms,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16984B),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Mulai Sekarang',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
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

/// 100% Native Vector Graphic Painter (Curved Bezier Wave Ribbons)
/// No background image used! Sharp at any resolution & 0 overhead.
class OnboardingVectorBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. TOP-LEFT Soft Sky & Cyan Waves
    final skyWavePaint1 = Paint()
      ..color = const Color(0xFFBAE6FD).withOpacity(0.35)
      ..style = PaintingStyle.fill;

    final pathTL1 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.75, 0)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.12,
        0,
        size.height * 0.16,
      )
      ..close();
    canvas.drawPath(pathTL1, skyWavePaint1);

    final skyWavePaint2 = Paint()
      ..color = const Color(0xFF93C5FD).withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final pathTL2 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.50, 0)
      ..quadraticBezierTo(
        size.width * 0.20,
        size.height * 0.16,
        0,
        size.height * 0.22,
      )
      ..close();
    canvas.drawPath(pathTL2, skyWavePaint2);

    // 2. BOTTOM-RIGHT Soft Emerald & Mint Waves
    final greenWavePaint1 = Paint()
      ..color = const Color(0xFF86EFAC).withOpacity(0.22)
      ..style = PaintingStyle.fill;

    final pathBR1 = Path()
      ..moveTo(size.width, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.88,
        size.width * 0.40,
        size.height,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(pathBR1, greenWavePaint1);

    final greenWavePaint2 = Paint()
      ..color = const Color(0xFF34D399).withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final pathBR2 = Path()
      ..moveTo(size.width, size.height * 0.84)
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.92,
        size.width * 0.60,
        size.height,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(pathBR2, greenWavePaint2);

    // 3. BOTTOM-LEFT Very Subtle Cyan Breeze Wave
    final cyanBreeze = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final pathBL = Path()
      ..moveTo(0, size.height * 0.90)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.94,
        size.width * 0.45,
        size.height,
      )
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(pathBL, cyanBreeze);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
