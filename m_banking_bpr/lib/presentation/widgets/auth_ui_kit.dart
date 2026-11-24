import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Unified visual tokens for all pre-login and authentication screens,
/// matching the myDMB Splash, Onboarding, and Home design system.
class AuthUiTokens {
  AuthUiTokens._();

  static const Color canvas = Color(0xFFF4F7FB);
  static const Color deepCobalt = Color(0xFF033172);
  static const Color royalBlue = Color(0xFF0550A6);
  static const Color azureBlue = Color(0xFF118CE0);
  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color softBlueBg = Color(0xFFEFF6FF);
  static const Color softBlueBorder = Color(0xFFBFDBFE);
  static const Color inputFill = Color(0xFFF8FAFC);
  static const Color inputBorder = Color(0xFFE2E8F0);
  static const Color titleDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [deepCobalt, royalBlue, azureBlue],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deepCobalt, royalBlue, azureBlue],
  );

  static const SystemUiOverlayStyle lightOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: canvas,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
}

/// Clean `#F4F7FB` canvas with subtle translucent blue-cyan curved waves
/// in the top-right corner, matching the myDMB Home/Menu/History screens.
class AuthSwooshCanvas extends StatelessWidget {
  const AuthSwooshCanvas({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AuthUiTokens.lightOverlay,
      child: Scaffold(
        backgroundColor: AuthUiTokens.canvas,
        body: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              left: 0,
              height: 260,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AuthSwooshPainter(),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _AuthSwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final softAzure = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          AuthUiTokens.azureBlue.withOpacity(0.14),
          AuthUiTokens.cyanAccent.withOpacity(0.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final path1 = Path()
      ..moveTo(w * 0.25, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.82)
      ..quadraticBezierTo(w * 0.62, h * 0.62, w * 0.25, 0)
      ..close();
    canvas.drawPath(path1, softAzure);

    final cyanRibbon = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomLeft,
        colors: [
          AuthUiTokens.cyanAccent.withOpacity(0.14),
          AuthUiTokens.azureBlue.withOpacity(0.03),
        ],
      ).createShader(Rect.fromLTWH(w * 0.45, 0, w * 0.55, h));

    final path2 = Path()
      ..moveTo(w * 0.52, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.56)
      ..quadraticBezierTo(w * 0.72, h * 0.36, w * 0.52, 0)
      ..close();
    canvas.drawPath(path2, cyanRibbon);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Top navigation bar for sub-auth screens (Forgot Password, OTP, Reset, Daftar).
class AuthTopHeader extends StatelessWidget {
  const AuthTopHeader({
    super.key,
    required this.onBack,
    required this.eyebrow,
    required this.title,
    required this.icon,
    this.trailing,
  });

  final VoidCallback onBack;
  final String eyebrow;
  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Material(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onBack,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AuthUiTokens.inputBorder),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AuthUiTokens.deepCobalt,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                trailing ?? const MyDmbBrandLogo(height: 42),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AuthUiTokens.softBlueBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AuthUiTokens.softBlueBorder),
                  ),
                  child: Icon(
                    icon,
                    color: AuthUiTokens.royalBlue,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AuthUiTokens.azureBlue,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AuthUiTokens.titleDark,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Crisp white card matching the myDMB design sheet.
class AuthSurfaceCard extends StatelessWidget {
  const AuthSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 22),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: AuthUiTokens.royalBlue.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Unified gradient pill CTA button (`#033172 -> #0550A6 -> #118CE0`).
class AuthGradientButton extends StatelessWidget {
  const AuthGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.height = 52,
    this.borderRadius = 26,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              enabled || isLoading ? AuthUiTokens.deepCobalt : const Color(0xFFE2E8F0),
          disabledBackgroundColor:
              isLoading ? AuthUiTokens.deepCobalt : const Color(0xFFE2E8F0),
          foregroundColor: Colors.white,
          disabledForegroundColor:
              isLoading ? Colors.white : const Color(0xFF94A3B8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
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
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

/// Official `myDMB` logo asset adapted for light (`#F4F7FB` / `#FFFFFF`) surfaces,
/// preserving the exact official geometry while shifting white strokes to `#033172`.
class MyDmbBrandLogo extends StatelessWidget {
  const MyDmbBrandLogo({
    super.key,
    this.height = 46,
    this.onDark = false,
  });

  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      onDark
          ? 'assets/images/mydmb_logo_official.png'
          : 'assets/images/mydmb_logo_light.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}
