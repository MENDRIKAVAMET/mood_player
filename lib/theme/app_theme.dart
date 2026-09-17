import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized app theme - all colors, text styles, spacing in one place
class AppTheme {
  // ═══════════════════════════════════════════════════════════════
  // COLORS
  // ═══════════════════════════════════════════════════════════════

  // Palette dérivée directement de l'icône de l'app : un dégradé
  // magenta-violet (#BF00FE) vers indigo (#5D00FF). Tout part de ces deux
  // teintes plutôt que d'un violet générique, pour que l'app et son icône
  // se ressemblent vraiment.
  static const Color brandTop = Color(0xFFBF00FE);
  static const Color brandBottom = Color(0xFF5D00FF);
  static const Color brandMid = Color(0xFF8A00FF);

  // Fonds : quasi-noirs très légèrement teintés de violet plutôt que du
  // gris neutre, pour que le dégradé de marque ne flotte pas au-dessus
  // d'un fond qui n'a rien à voir.
  static const Color backgroundPrimary = Color(0xFF07040D);
  static const Color backgroundSecondary = Color(0xFF0D0716);
  static const Color backgroundTertiary = Color(0xFF130B20);
  static const Color backgroundCard = Color(0xFF16102A);
  static const Color backgroundCardElevated = Color(0xFF1F1738);

  // Surfaces translucides : à poser sur un fond dégradé, elles laissent la
  // couleur transparaître au lieu de l'aplatir. C'est ce qui donne de la
  // profondeur sans multiplier les aplats.
  static const Color surfaceGlass = Color(0x14FFFFFF);
  static const Color surfaceGlassStrong = Color(0x1FFFFFFF);
  static const Color surfaceTint = Color(0x1A8A00FF);

  static const Color accentPrimary = Color(0xFFA855F7);
  static const Color accentSecondary = Color(0xFFC94DFF);
  static const Color accentWarm = Color(0xFFFF5FA2);
  static const Color accentSuccess = Color(0xFF10B981);
  static const Color accentWarning = Color(0xFFFF6B35);
  static const Color accentError = Color(0xFFE63946);

  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFBFB3D4);
  static const Color textTertiary = Color(0xFF76688F);
  static const Color textInverse = Color(0xFF07040D);

  // Divider / Border — translucides, pour qu'ils se fondent sur n'importe
  // quel fond au lieu de tracer une ligne grise franche.
  static const Color divider = Color(0x1AFFFFFF);
  static const Color border = Color(0x26FFFFFF);

  // ═══════════════════════════════════════════════════════════════
  // DÉGRADÉS
  // ═══════════════════════════════════════════════════════════════

  /// Le dégradé de marque, tel quel (boutons pleins, éléments actifs).
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brandTop, brandBottom],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Fond d'écran : la marque en très faible opacité en haut, qui se fond
  /// dans le noir. Remplace l'ancien bloc bleu-gris plaqué en haut.
  static const LinearGradient screenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x3DBF00FE),
      Color(0x1A5D00FF),
      backgroundPrimary,
    ],
    stops: [0.0, 0.22, 0.55],
  );

  /// Surface de carte : un voile clair très léger, en diagonale.
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
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
  static const double radiusM = 10.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusFull = 999.0;

  // ═══════════════════════════════════════════════════════════════
  // ELEVATIONS / SHADOWS
  // ═══════════════════════════════════════════════════════════════

  static List<BoxShadow> get shadowSmall => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMedium => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLarge => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> coloredShadow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.3),
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
  // TEXT STYLES — Space Grotesk for display/headlines (the app's
  // wordmark and section titles get a bit of character), Inter for
  // body/labels (stays neutral and legible at small sizes/high density).
  // ═══════════════════════════════════════════════════════════════

  static TextStyle get displayLarge => GoogleFonts.spaceGrotesk(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.8,
    height: 1.15,
  );

  static TextStyle get displayMedium => GoogleFonts.spaceGrotesk(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.4,
    height: 1.2,
  );

  static TextStyle get headlineLarge => GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.2,
    height: 1.25,
  );

  static TextStyle get headlineMedium => GoogleFonts.spaceGrotesk(
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

  /// Carte translucide : un voile clair en dégradé posé sur le fond, au
  /// lieu d'un aplat gris. Le fond de l'écran transparaît, ce qui évite
  /// l'effet « rectangles gris empilés ».
  static BoxDecoration get cardDecoration => BoxDecoration(
    gradient: cardGradient,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: border, width: 1),
  );

  /// Variante teintée par une couleur d'ambiance (mood, pochette…).
  static BoxDecoration tintedCardDecoration(Color tint) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        tint.withValues(alpha: 0.20),
        tint.withValues(alpha: 0.04),
      ],
    ),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: tint.withValues(alpha: 0.28), width: 1),
  );

  static BoxDecoration get cardElevatedDecoration => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0x2EFFFFFF), Color(0x14FFFFFF)],
    ),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: border, width: 1),
    boxShadow: shadowSmall,
  );

  static BoxDecoration get glassDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.14),
        Colors.white.withValues(alpha: 0.04),
      ],
    ),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1),
  );

  /// The app's signature ambient treatment: a soft indigo-violet glow
  /// that fades to warm coral, used behind the mini player and other
  /// "always-on" surfaces so the app's mood-shifting identity is felt
  /// even when nothing is playing yet. Pass a mood's own color to tint
  /// it toward whatever's currently playing instead.
  static LinearGradient auroraGradient({Color? tint}) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          (tint ?? accentPrimary).withValues(alpha: 0.22),
          accentSecondary.withValues(alpha: 0.10),
          backgroundCard,
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
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackHeight: 4,
        overlayColor: accentPrimary.withValues(alpha: 0.2),
      ),
      iconTheme: const IconThemeData(color: textPrimary, size: 24),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
    );
  }
}
