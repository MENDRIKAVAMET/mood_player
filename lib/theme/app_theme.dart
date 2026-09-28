import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized app theme - all colors, text styles, spacing in one place
class AppTheme {
  // ═══════════════════════════════════════════════════════════════
  // COLORS
  // ═══════════════════════════════════════════════════════════════

  // Palette sobre : gris graphite neutres, UN seul accent chaud (corail)
  // appliqué à plat - jamais en dégradé ni en halo - et des ambiances
  // (moods) moyennement saturées.
  static const Color brandTop = Color(0xFFFF6B57);
  static const Color brandBottom = Color(0xFFFF6B57);
  static const Color brandMid = Color(0xFFFF6B57);

  static const Color backgroundPrimary = Color(0xFF0B0B0C);
  static const Color backgroundSecondary = Color(0xFF111113);
  static const Color backgroundTertiary = Color(0xFF161618);
  static const Color backgroundCard = Color(0xFF161618);
  static const Color backgroundCardElevated = Color(0xFF1E1E21);

  static const Color surfaceGlass = Color(0x0FFFFFFF);
  static const Color surfaceGlassStrong = Color(0x1AFFFFFF);
  static const Color surfaceTint = Color(0x0FFFFFFF);

  static const Color accentPrimary = Color(0xFFFF6B57);
  static const Color accentSecondary = Color(0xFFE8B86D);
  static const Color accentWarm = Color(0xFFE8B86D);
  static const Color accentSuccess = Color(0xFF6FAE8B);
  static const Color accentWarning = Color(0xFFC79A5B);
  static const Color accentError = Color(0xFFD16666);

  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA8A8AD);
  // Texte tertiaire : éclairci de #76688F à #8B7EAB - le premier ne
  // passait pas le contraste minimum WCAG AA sur le fond quasi-noir de
  // l'app (~4.0:1, sous les 4.5:1 requis), alors que c'est justement la
  // couleur utilisée pour le texte le plus petit (badges, labels).
  static const Color textTertiary = Color(0xFF808086);
  static const Color textInverse = Color(0xFF0B0B0C);

  // Divider / Border — translucides, pour qu'ils se fondent sur n'importe
  // quel fond au lieu de tracer une ligne grise franche.
  static const Color divider = Color(0x1AFFFFFF);
  static const Color border = Color(0x26FFFFFF);

  // ═══════════════════════════════════════════════════════════════
  // DÉGRADÉS
  // ═══════════════════════════════════════════════════════════════

  // Les « dégradés » ci-dessous sont volontairement plats (deux fois la
  // même couleur) : le type LinearGradient est conservé pour ne pas
  // toucher tous les écrans, mais il n'y a plus aucun effet de dégradé.

  static const LinearGradient brandGradient = LinearGradient(
    colors: [accentPrimary, accentPrimary],
  );

  static const LinearGradient screenGradient = LinearGradient(
    colors: [backgroundPrimary, backgroundPrimary],
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0x0FFFFFFF), Color(0x0FFFFFFF)],
  );

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
  static const double radiusM = 8.0;
  static const double radiusL = 12.0;
  static const double radiusXL = 20.0;
  static const double radiusFull = 999.0;

  // ═══════════════════════════════════════════════════════════════
  // ELEVATIONS / SHADOWS
  // ═══════════════════════════════════════════════════════════════

  static List<BoxShadow> get shadowSmall => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMedium => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.18),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLarge => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  /// Plus d'ombre colorée : conservée pour compatibilité, mais sans effet.
  static List<BoxShadow> coloredShadow(Color color) => const [];

  // ═══════════════════════════════════════════════════════════════
  // ANIMATION DURATIONS
  // ═══════════════════════════════════════════════════════════════

  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);
  static const Duration animVerySlow = Duration(milliseconds: 600);
  static const Duration animPageTransition = Duration(milliseconds: 350);

  // ═══════════════════════════════════════════════════════════════
  // TEXT STYLES — Space Grotesk for display/headlines (the app's
  // wordmark and section titles get a bit of character), Inter for
  // body/labels (stays neutral and legible at small sizes/high density).
  // ═══════════════════════════════════════════════════════════════

  static TextStyle get displayLarge => GoogleFonts.inter(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.9,
    height: 1.15,
  );

  static TextStyle get displayMedium => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static TextStyle get headlineLarge => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.2,
    height: 1.25,
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

  /// Carte : aplat neutre, fine bordure.
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: backgroundCard,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: divider, width: 1),
  );

  /// Variante « teintée » : la teinte n'est plus qu'un très léger voile.
  static BoxDecoration tintedCardDecoration(Color tint) => BoxDecoration(
    color: Color.alphaBlend(tint.withValues(alpha: 0.06), backgroundCard),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: divider, width: 1),
  );

  static BoxDecoration get cardElevatedDecoration => BoxDecoration(
    color: backgroundCardElevated,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: divider, width: 1),
  );

  static BoxDecoration get glassDecoration => BoxDecoration(
    color: const Color(0x14FFFFFF),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: divider, width: 1),
  );

  /// Fond des surfaces « toujours visibles » (mini lecteur…) : quasi
  /// uni, avec à peine une trace de la couleur du morceau.
  static LinearGradient auroraGradient({Color? tint}) => LinearGradient(
        colors: [
          Color.alphaBlend(
            (tint ?? accentSecondary).withValues(alpha: 0.07),
            backgroundCardElevated,
          ),
          backgroundCardElevated,
        ],
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
      cardTheme: CardThemeData(
        color: backgroundCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentPrimary,
        inactiveTrackColor: textTertiary.withValues(alpha: 0.3),
        thumbColor: accentPrimary,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackHeight: 3,
        overlayColor: accentPrimary.withValues(alpha: 0.2),
      ),
      iconTheme: const IconThemeData(color: textPrimary, size: 24),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
    );
  }
}
