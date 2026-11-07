import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Bank DMB Logo matching Figma header
class DmbLogoHeader extends StatelessWidget {
  final double scale;
  const DmbLogoHeader({super.key, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 3 stylized people logo (Emerald Green & Navy Blue)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.groups_rounded, color: AppColors.primary, size: 26 * scale),
                  const SizedBox(width: 4),
                  Text(
                    'Bank DMB',
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w900,
                      color: AppColors.dmbNavy,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            'bpr dana mandiri bogor',
            style: TextStyle(
              fontSize: 9 * scale,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Onboarding Illustration: Isometric phones with transferring coin & plant
class OnboardingTransferIllustration extends StatelessWidget {
  const OnboardingTransferIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 240,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Isometric platform shadow
          Positioned(
            bottom: 20,
            child: Container(
              width: 250,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          // Two Phones
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Phone 1 (Left)
              Container(
                width: 82,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(-4, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFB703),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '\$',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Phone 2 (Right)
              Container(
                width: 82,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(4, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFB703),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '\$',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Transfer Arc Arrow
          Positioned(
            top: 25,
            child: Icon(
              Icons.sync_alt_rounded,
              size: 40,
              color: AppColors.dmbNavy,
            ),
          ),
          // Potted plant on the left
          Positioned(
            left: 14,
            bottom: 45,
            child: Column(
              children: [
                Icon(Icons.eco_rounded, size: 28, color: AppColors.primary),
                Container(
                  width: 20,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          // Coins stack on the right
          Positioned(
            right: 20,
            bottom: 45,
            child: Column(
              children: List.generate(
                3,
                (i) => Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 26,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB703),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFB8500), width: 1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Login Illustration: Phone with rolling receipt, card & coins
class LoginReceiptIllustration extends StatelessWidget {
  const LoginReceiptIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 180,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background soft circle
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF1F5F9).withOpacity(0.8),
            ),
          ),
          // Phone device with green screen
          Transform.rotate(
            angle: 0.1,
            child: Container(
              width: 90,
              height: 135,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1E293B), width: 2.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // White debit card coming out on left
          Positioned(
            left: 20,
            top: 25,
            child: Transform.rotate(
              angle: -0.25,
              child: Container(
                width: 75,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155), width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 16,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    Container(width: 40, height: 4, color: const Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ),
          // Rolling receipt paper
          Positioned(
            right: 40,
            bottom: 24,
            child: Container(
              width: 52,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155), width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  4,
                  (index) => Container(
                    width: 34,
                    height: 3,
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
          ),
          // Floating coins
          Positioned(
            left: 36,
            bottom: 30,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFF64748B), width: 1.5),
              ),
              child: const Center(
                child: Text('DMB', style: TextStyle(fontSize: 6, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forgot Password Illustration: Hand holding phone with padlock bubble
class PhoneLockIllustration extends StatelessWidget {
  const PhoneLockIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 180,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background soft circle
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF1F5F9).withOpacity(0.9),
            ),
          ),
          // Hand holding phone
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E293B), width: 2.2),
                ),
                padding: const EdgeInsets.all(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          // Hand cuff motif below
          Positioned(
            bottom: 12,
            right: 48,
            child: Container(
              width: 48,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: CircleAvatar(radius: 3, backgroundColor: Colors.white),
                ),
              ),
            ),
          ),
          // Speech Bubble with Padlock & Asterisks
          Positioned(
            top: 15,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B), width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(Icons.lock_rounded, size: 24, color: AppColors.primary),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '•••••',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

