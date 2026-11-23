import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';

enum ValidationType {
  error,
  warning,
  success,
  info,
}

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
          primaryColor: AppColors.danger,
          backgroundColor: AppColors.surface,
          borderColor: AppColors.dangerBorder,
          iconBadgeBg: AppColors.dangerLight,
          titleColor: Color(0xFF991B1B),
          messageColor: AppColors.textSecondary,
          icon: Icons.error_outline_rounded,
          defaultTitle: 'Validasi Diperlukan',
        );
      case ValidationType.warning:
        return const _ValidationStyle(
          primaryColor: AppColors.warning,
          backgroundColor: AppColors.surface,
          borderColor: AppColors.warningBorder,
          iconBadgeBg: AppColors.warningLight,
          titleColor: Color(0xFF92400E),
          messageColor: AppColors.textSecondary,
          icon: Icons.warning_amber_rounded,
          defaultTitle: 'Perhatian',
        );
      case ValidationType.success:
        return const _ValidationStyle(
          primaryColor: AppColors.dmbGreen,
          backgroundColor: AppColors.surface,
          borderColor: AppColors.successBorder,
          iconBadgeBg: AppColors.successLight,
          titleColor: Color(0xFF14532D),
          messageColor: AppColors.textSecondary,
          icon: Icons.check_circle_outline_rounded,
          defaultTitle: 'Berhasil',
        );
      case ValidationType.info:
        return const _ValidationStyle(
          primaryColor: AppColors.primaryNavy,
          backgroundColor: AppColors.surface,
          borderColor: AppColors.primaryBorder,
          iconBadgeBg: AppColors.primaryLight,
          titleColor: AppColors.titleDark,
          messageColor: AppColors.textSecondary,
          icon: Icons.info_outline_rounded,
          defaultTitle: 'Informasi',
        );
    }
  }
}

class AppToast {
  AppToast._();

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    ValidationType type = ValidationType.error,
    Duration duration = const Duration(milliseconds: 3800),
    VoidCallback? onDismiss,
  }) {
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
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              color: AppColors.textMuted,
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
