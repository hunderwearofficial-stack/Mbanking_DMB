import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// Bank-standard reusable loading overlay for blocking server requests
/// (Login, OTP, Activation, Product Submission) without creating extra full-screen pages.
class AppLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final Widget child;

  const AppLoadingOverlay({
    super.key,
    required this.isLoading,
    this.message = 'Mohon tunggu...',
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: const Color(0x66091324),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.14),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.8,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryNavy),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.titleDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Modern bank-style white rounded popup card for offline / server-unreachable states.
/// Works both as a full-screen overlay (e.g. on SplashScreen) and as a modal dialog via [showModal].
class AppConnectionErrorView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool isRetrying;
  final bool showRetryButton;
  final Color backgroundColor;
  final bool showBackdropScrim;

  const AppConnectionErrorView({
    super.key,
    this.title = 'Koneksi internet terputus',
    this.message =
        'Periksa jaringan seluler, paket data, atau Wi-Fi Anda, lalu silakan coba lagi.',
    this.onRetry,
    this.isRetrying = false,
    this.showRetryButton = false,
    this.backgroundColor = const Color(0xFF091324),
    this.showBackdropScrim = true,
  });

  /// Shows this popup card as a modal dialog from any screen when internet/server fails.
  static Future<void> showModal(
    BuildContext context, {
    String title = 'Koneksi internet terputus',
    String message =
        'Periksa jaringan seluler, paket data, atau Wi-Fi Anda, lalu silakan coba lagi.',
    required Future<void> Function() onRetry,
    bool barrierDismissible = false,
  }) {
    bool retrying = false;
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: const Color(0x99091324),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return PopScope(
              canPop: barrierDismissible,
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                alignment: Alignment.bottomCenter,
                insetPadding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
                child: _ConnectionErrorCard(
                  title: title,
                  message: message,
                  isRetrying: retrying,
                  onRetry: () async {
                    if (retrying) return;
                    setModalState(() => retrying = true);
                    try {
                      await onRetry();
                      if (dialogCtx.mounted) {
                        Navigator.of(dialogCtx).pop();
                      }
                    } finally {
                      if (ctx.mounted) {
                        setModalState(() => retrying = false);
                      }
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: showBackdropScrim
          ? const Color(0xA6091324)
          : backgroundColor.withOpacity(0.92),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: _ConnectionErrorCard(
              title: title,
              message: message,
              isRetrying: isRetrying,
              showRetryButton: showRetryButton,
              onRetry: onRetry,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionErrorCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool isRetrying;
  final bool showRetryButton;

  const _ConnectionErrorCard({
    required this.title,
    required this.message,
    this.onRetry,
    required this.isRetrying,
    this.showRetryButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                'assets/images/connection_lost.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFDFF7F4),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 46,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.left,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.left,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              color: const Color(0xFF4B5563),
              height: 1.48,
            ),
          ),
          if (showRetryButton && onRetry != null) ...[
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isRetrying ? null : onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primaryNavy.withOpacity(0.65),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: isRetrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 19),
                label: Text(
                  isRetrying ? 'Menghubungkan...' : 'Coba Lagi',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
