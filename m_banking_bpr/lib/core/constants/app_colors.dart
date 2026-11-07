import 'package:flutter/material.dart';

/// Bank DMB Official Design Palette
/// 100% Uniform with Web Admin Backoffice & wondr by BNI modern style
class AppColors {
  // Official Backoffice Primary Teal Palette
  static const Color primary = Color(0xFF00897B); // Executive Teal (Backoffice Active Theme)
  static const Color primaryDark = Color(0xFF004D40); // Deep Midnight Teal (Card Luxury)
  static const Color primaryMedium = Color(0xFF00796B);
  static const Color primaryLight = Color(0xFFE0F2F1); // Soft Teal 50
  static const Color primaryMint = Color(0xFFF0FDFA); // Subtle Mint tint

  // Corporate DMB Identity Colors
  static const Color dmbNavy = Color(0xFF0A3B66); // DMB Corporate Logo Blue
  static const Color dmbNavyDark = Color(0xFF062440);
  static const Color accentGreen = Color(0xFF16984B); // DMB Vibrant Green

  // Surfaces & Backgrounds (Clean Modern Canvas khas wondr)
  static const Color background = Color(0xFFF8FAFC); // Slate-50 Crisp Off-White
  static const Color surface = Colors.white;
  static const Color card = Colors.white;
  static const Color inputBackground = Color(0xFFF8FAFC);

  // Status & Financial Indicators
  static const Color income = Color(0xFF00897B); // Uang Masuk (Teal)
  static const Color incomeLight = Color(0xFFE0F2F1);
  static const Color expense = Color(0xFFE11D48); // Uang Keluar (Rose Red)
  static const Color expenseLight = Color(0xFFFFE4E6);
  static const Color success = Color(0xFF00897B);
  static const Color successLight = Color(0xFFE0F2F1);
  static const Color danger = Color(0xFFE11D48);
  static const Color dangerLight = Color(0xFFFFE4E6);
  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFEF3C7);

  // Typography & Neutral Colors (Slate Scale)
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF94A3B8); // Slate 400
  static const Color border = Color(0xFFE2E8F0); // Slate 200 Hairline
  static const Color borderSubtle = Color(0xFFF1F5F9);
  static const Color borderFocused = Color(0xFF00897B);
  static const Color divider = Color(0xFFE2E8F0);

  // Button States
  static const Color buttonDisabled = Color(0xFFE2E8F0);
  static const Color buttonDisabledText = Color(0xFF94A3B8);

  // Aliases for compatibility with existing codebase
  static const Color secondary = primary;
  static const Color secondaryLight = primaryLight;
  static const Color accentGreenLight = primaryLight;
  static const Color accentOrange = warning;
  static const Color accentOrangeLight = warningLight;
  static const Color accentGold = warning;
  static const Color accentGoldLight = warningLight;
}
