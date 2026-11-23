import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Executive Navy & Royal Blue Palette
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color primaryDark = Color(0xFF071A3E);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);

  // Typography & Neutral Palette
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;

  // Semantic Status Colors
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color success = Color(0xFF16A34A);

  // Extended Surface & Tinted Badges
  static const Color primaryLight = Color(0xFFEFF6FF);
  static const Color primaryBorder = Color(0xFFBFDBFE);
  static const Color successLight = Color(0xFFF0FDF4);
  static const Color successBorder = Color(0xFFBBF7D0);
  static const Color dangerLight = Color(0xFFFEF2F2);
  static const Color dangerBorder = Color(0xFFFECACA);
  static const Color warningLight = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);

  // Backward-compatible semantic aliases
  static const Color primary = primaryNavy;
  static const Color primaryMedium = royalBlue;
  static const Color primaryMint = successLight;
  static const Color dmbNavy = primaryNavy;
  static const Color dmbNavyDark = primaryDark;
  static const Color accentGreen = dmbGreen;
  static const Color accentGreenLight = successLight;
  static const Color background = bgCanvas;
  static const Color card = surface;
  static const Color inputBackground = bgCanvas;
  static const Color income = dmbGreen;
  static const Color incomeLight = successLight;
  static const Color expense = danger;
  static const Color expenseLight = dangerLight;
  static const Color border = borderLight;
  static const Color borderSubtle = Color(0xFFF1F5F9);
  static const Color borderFocused = royalBlue;
  static const Color divider = borderLight;
  static const Color buttonDisabled = borderLight;
  static const Color buttonDisabledText = Color(0xFF94A3B8);
  static const Color secondary = royalBlue;
  static const Color secondaryLight = primaryLight;
  static const Color accentOrange = warning;
  static const Color accentOrangeLight = warningLight;
  static const Color accentGold = warning;
  static const Color accentGoldLight = warningLight;
}
