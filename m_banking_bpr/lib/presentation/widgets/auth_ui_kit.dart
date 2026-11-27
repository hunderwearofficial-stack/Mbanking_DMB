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

  static const SystemUiOverlayStyle darkHeaderOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: canvas,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
}

/// Clean `#F4F7FB` canvas with optional Bank DMB Navy curved header backdrop
/// (used across pre-login/auth screens) or subtle top-right waves for inner screens.
class AuthSwooshCanvas extends StatelessWidget {
  const AuthSwooshCanvas({
    super.key,
    required this.child,
    this.navyHeaderHeight = 0,
  });

  final Widget child;
  final double navyHeaderHeight;

  @override
  Widget build(BuildContext context) {
    final hasNavyHeader = navyHeaderHeight > 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: hasNavyHeader
          ? AuthUiTokens.darkHeaderOverlay
          : AuthUiTokens.lightOverlay,
      child: Scaffold(
        backgroundColor: AuthUiTokens.canvas,
        body: Stack(
          children: [
            if (hasNavyHeader)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: navyHeaderHeight,
                child: IgnorePointer(
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
                              AuthUiTokens.deepCobalt.withValues(alpha: 0.85),
                              AuthUiTokens.royalBlue.withValues(alpha: 0.38),
                            ],
                            stops: const [0.0, 0.5, 1.0],
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
                              AuthUiTokens.deepCobalt.withValues(alpha: 0.5),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
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
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onBack,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                trailing ?? const MyDmbBrandLogo(height: 42, onDark: true),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                  ),
                  child: Icon(
                    icon,
                    color: AuthUiTokens.cyanAccent,
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
                          color: Color(0xFFBAE6FD),
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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

/// Reusable Bank DMB Navy Curved Header for inner banking screens
/// (Mutasi, Deposito, Pinjaman, Info Rekening, Katalog Produk, dll).
class DmbNavyHeader extends StatelessWidget {
  const DmbNavyHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.onBack,
    this.actionIcon,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AuthUiTokens.deepCobalt,
            AuthUiTokens.royalBlue,
            Color(0xFF02204D),
          ],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Row(
            children: [
              if (showBack) ...[
                Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onBack ?? () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.35,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (actionIcon != null && onAction != null)
                Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onAction,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Icon(
                        actionIcon,
                        size: 19,
                        color: Colors.white,
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

/// Unified clean light header matching Pusat Bantuan, Notifikasi, and Akun Saya.
/// Edit this widget once to update the header across all inner screens.
class DmbPageHeader extends StatelessWidget {
  const DmbPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.onBack,
    this.actionIcon,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Row(
        children: [
          if (showBack) ...[
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack ?? () => Navigator.of(context).pop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AuthUiTokens.inputBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 19,
                    color: AuthUiTokens.deepCobalt,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AuthUiTokens.deepCobalt,
                    letterSpacing: -0.35,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AuthUiTokens.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionIcon != null && onAction != null)
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAction,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AuthUiTokens.inputBorder),
                  ),
                  child: Icon(
                    actionIcon,
                    size: 19,
                    color: AuthUiTokens.deepCobalt,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Unified squircle icon container (`#EFF6FF` + `#033172` icon) used across cards.
class DmbIconSquircle extends StatelessWidget {
  const DmbIconSquircle({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.color = AuthUiTokens.deepCobalt,
    this.backgroundColor = AuthUiTokens.softBlueBg,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}
