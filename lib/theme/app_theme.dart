import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized app theme - all colors, text styles, spacing in one place
class AppTheme {
  // ═══════════════════════════════════════════════════════════════
  // COLORS
  // ═══════════════════════════════════════════════════════════════

  // Background colors
  static const Color backgroundPrimary = Color(0xFF0A0A0A);
  static const Color backgroundSecondary = Color(0xFF121212);
  static const Color backgroundTertiary = Color(0xFF181818);
  static const Color backgroundCard = Color(0xFF1E1E1E);
  static const Color backgroundCardElevated = Color(0xFF282828);

  // Accent colors
  static const Color accentPrimary = Color(0xFF1DB954);
  static const Color accentSecondary = Color(0xFF1ED760);
  static const Color accentSuccess = Color(0xFF10B981);
  static const Color accentWarning = Color(0xFFFF6B35);
  static const Color accentError = Color(0xFFE63946);

  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF6A6A6A);
  static const Color textInverse = Color(0xFF000000);

  // Divider / Border
  static const Color divider = Color(0xFF282828);
  static const Color border = Color(0xFF333333);

  // ═══════════════════════════════════════════════════════════════
  // SPACING
  // ═══════════════════════════════════════════════════════════════

  static const double spacingXXS = 2.0;
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 12.0;
  static const double spacingL = 16.0;
  static const double spacingXL = 24.0;
  static const double spacingXXL = 32.0;
  static const double spacingXXXL = 48.0;

  // ═══════════════════════════════════════════════════════════════
  // BORDER RADIUS
  // ═══════════════════════════════════════════════════════════════

  static const double radiusS = 6.0;
  static const double radiusM = 10.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusFull = 999.0;

  // ═══════════════════════════════════════════════════════════════
  // ELEVATIONS / SHADOWS
  // ═══════════════════════════════════════════════════════════════

  static List<BoxShadow> get shadowSmall => [
    BoxShadow(
      color: Colors.black.withOpacity(0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMedium => [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLarge => [
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> coloredShadow(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.3),
      blurRadius: 40,
      spreadRadius: -4,
      offset: const Offset(0, 8),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════
  // ANIMATION DURATIONS
  // ═══════════════════════════════════════════════════════════════

  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);
  static const Duration animVerySlow = Duration(milliseconds: 600);
  static const Duration animPageTransition = Duration(milliseconds: 350);

  // ═══════════════════════════════════════════════════════════════
  // TEXT STYLES (using Google Fonts - Inter)
  // ═══════════════════════════════════════════════════════════════

  static TextStyle get displayLarge => GoogleFonts.inter(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: textPrimary,
    letterSpacing: -1.0,
    height: 1.2,
  );

  static TextStyle get displayMedium => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static TextStyle get headlineLarge => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static TextStyle get headlineMedium => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.3,
  );

  static TextStyle get titleLarge => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.4,
  );

  static TextStyle get titleMedium => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.4,
  );

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.5,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textTertiary,
    height: 1.4,
  );

  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: 0.5,
    height: 1.4,
  );

  static TextStyle get labelMedium => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    letterSpacing: 0.3,
    height: 1.3,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: textTertiary,
    letterSpacing: 0.5,
    height: 1.3,
  );

  // ═══════════════════════════════════════════════════════════════
  // DECORATIONS
  // ═══════════════════════════════════════════════════════════════

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: backgroundCard,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: border.withOpacity(0.3), width: 1),
  );

  static BoxDecoration get cardElevatedDecoration => BoxDecoration(
    color: backgroundCardElevated,
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: shadowSmall,
  );

  static BoxDecoration get glassDecoration => BoxDecoration(
    color: Colors.black.withOpacity(0.5),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
  );

  // ═══════════════════════════════════════════════════════════════
  // THEME DATA
  // ═══════════════════════════════════════════════════════════════

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundPrimary,
      primaryColor: accentPrimary,
      colorScheme: const ColorScheme.dark(
        primary: accentPrimary,
        secondary: accentSecondary,
        surface: backgroundSecondary,
        error: accentError,
        onPrimary: textInverse,
        onSecondary: textInverse,
        onSurface: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: headlineLarge,
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardTheme(
        color: backgroundCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentPrimary,
        inactiveTrackColor: textTertiary.withOpacity(0.3),
        thumbColor: accentPrimary,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackHeight: 4,
        overlayColor: accentPrimary.withOpacity(0.2),
      ),
      iconTheme: const IconThemeData(color: textPrimary, size: 24),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
    );
  }
}
