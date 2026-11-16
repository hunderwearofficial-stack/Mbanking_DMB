import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Jenis validasi / umpan balik sistem
enum ValidationType {
  error,
  warning,
  success,
  info,
}

/// Helper konfigurasi styling visual per tipe validasi
class _ValidationStyle {
  final Color primaryColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color iconBadgeBg;
  final Color titleColor;
  final Color messageColor;
  final IconData icon;
  final String defaultTitle;

  const _ValidationStyle({
    required this.primaryColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconBadgeBg,
    required this.titleColor,
    required this.messageColor,
    required this.icon,
    required this.defaultTitle,
  });

  static _ValidationStyle fromType(ValidationType type) {
    switch (type) {
      case ValidationType.error:
        return const _ValidationStyle(
          primaryColor: Color(0xFFEF4444), // Vibrant Red
          backgroundColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFFFECDD3), // Soft Rose Border
          iconBadgeBg: Color(0xFFFFF1F2), // Rose Wash
          titleColor: Color(0xFF991B1B), // Deep Maroon
          messageColor: Color(0xFF334155), // Slate 700
          icon: Icons.error_outline_rounded,
          defaultTitle: 'Validasi Diperlukan',
        );
      case ValidationType.warning:
        return const _ValidationStyle(
          primaryColor: Color(0xFFF59E0B), // Vibrant Amber
          backgroundColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFFFDE68A), // Soft Amber Border
          iconBadgeBg: Color(0xFFFFFBEB), // Amber Wash
          titleColor: Color(0xFF92400E), // Deep Amber
          messageColor: Color(0xFF334155),
          icon: Icons.warning_amber_rounded,
          defaultTitle: 'Perhatian',
        );
      case ValidationType.success:
        return const _ValidationStyle(
          primaryColor: Color(0xFF16984B), // DMB Green
          backgroundColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFFA7F3D0), // Soft Emerald Border
          iconBadgeBg: Color(0xFFF0FDF4), // Mint Wash
          titleColor: Color(0xFF14532D), // Deep Forest Green
          messageColor: Color(0xFF334155),
          icon: Icons.check_circle_outline_rounded,
          defaultTitle: 'Berhasil',
        );
      case ValidationType.info:
        return const _ValidationStyle(
          primaryColor: Color(0xFF0B356D), // Corporate Navy
          backgroundColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFFBAE6FD), // Soft Sky Border
          iconBadgeBg: Color(0xFFEFF6FF), // Sky Wash
          titleColor: Color(0xFF1E3A8A), // Deep Blue
          messageColor: Color(0xFF334155),
          icon: Icons.info_outline_rounded,
          defaultTitle: 'Informasi',
        );
    }
  }
}

/// Global Toast / Feedback Manager untuk Mobile Banking DMB
/// Menampilkan notifikasi validasi dengan desain premium perbankan (modern floating capsule)
class AppToast {
  AppToast._();

  /// Menampilkan pesan toast global modern
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    ValidationType type = ValidationType.error,
    Duration duration = const Duration(milliseconds: 3800),
    VoidCallback? onDismiss,
  }) {
    // Berikan respons haptic halus saat validasi muncul
    try {
      if (type == ValidationType.error) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        padding: EdgeInsets.zero,
        content: AppToastCard(
          message: message,
          title: title,
          type: type,
          onClose: () {
            messenger.hideCurrentSnackBar();
            onDismiss?.call();
          },
        ),
      ),
    );
  }

  /// Shortcut untuk Validasi Error
  static void showError(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Validasi Diperlukan',
      type: ValidationType.error,
      duration: duration,
    );
  }

  /// Shortcut untuk Peringatan (Warning)
  static void showWarning(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3800),
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Perhatian',
      type: ValidationType.warning,
      duration: duration,
    );
  }

  /// Shortcut untuk Berhasil (Success)
  static void showSuccess(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Berhasil',
      type: ValidationType.success,
      duration: duration,
    );
  }

  /// Shortcut untuk Info
  static void showInfo(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Informasi',
      type: ValidationType.info,
      duration: duration,
    );
  }
}

/// Extension BuildContext agar pemanggilan validasi di setiap screen sangat bersih dan ringkas:
/// Contoh: `context.showErrorToast('Nomor handphone wajib diisi');`
extension AppValidationContextExtension on BuildContext {
  void showErrorToast(String message, {String? title}) =>
      AppToast.showError(this, message, title: title);

  void showWarningToast(String message, {String? title}) =>
      AppToast.showWarning(this, message, title: title);

  void showSuccessToast(String message, {String? title}) =>
      AppToast.showSuccess(this, message, title: title);

  void showInfoToast(String message, {String? title}) =>
      AppToast.showInfo(this, message, title: title);
}

/// Widget Card Toast yang elegan dengan aksen border halus dan ikon squircle
class AppToastCard extends StatelessWidget {
  final String message;
  final String? title;
  final ValidationType type;
  final VoidCallback? onClose;

  const AppToastCard({
    super.key,
    required this.message,
    this.title,
    this.type = ValidationType.error,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final style = _ValidationStyle.fromType(type);

    return Container(
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: style.borderColor, width: 1.2),
        boxShadow: [
          // Soft ambient drop shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          // Subtle colored glow shadow
          BoxShadow(
            color: style.primaryColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Left Color Accent Ribbon
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: style.primaryColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                ),
              ),

              // 2. Main Content Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Circular Icon Squircle Badge
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: style.iconBadgeBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: style.primaryColor.withOpacity(0.18),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          style.icon,
                          color: style.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Text Content (Title & Message)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title ?? style.defaultTitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: style.titleColor,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              message,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: style.messageColor,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Close Dismiss Button
                      if (onClose != null) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: onClose,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ],
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

/// Widget Validasi In-Form (Inline Card)
/// Menggantikan tampilan "warna merah kotak kaku" pada form dengan desain premium & ramah pengguna.
class InlineValidationCard extends StatelessWidget {
  final String message;
  final String? title;
  final ValidationType type;
  final VoidCallback? onDismiss;
  final EdgeInsetsGeometry? margin;

  const InlineValidationCard({
    super.key,
    required this.message,
    this.title,
    this.type = ValidationType.error,
    this.onDismiss,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  @override
  Widget build(BuildContext context) {
    final style = _ValidationStyle.fromType(type);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: style.iconBadgeBg.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: style.primaryColor.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: style.backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: style.borderColor),
            ),
            child: Icon(
              style.icon,
              color: style.primaryColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),

          // Message & Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: style.titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: style.messageColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          // Optional dismiss button
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: style.messageColor.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
