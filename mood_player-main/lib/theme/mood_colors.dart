import 'package:flutter/material.dart';
import '../models/track.dart';

/// Color palette for each mood type
class MoodColors {
  final Color primary;
  final Color secondary;
  final Color gradientStart;
  final Color gradientEnd;
  final Color glow;
  final Color cardBg;

  const MoodColors({
    required this.primary,
    required this.secondary,
    required this.gradientStart,
    required this.gradientEnd,
    required this.glow,
    required this.cardBg,
  });

  /// Teinte / saturation / luminosité de la couleur principale de chaque
  /// mood. Tout le reste de la palette (secondaire, fonds, halo) en est
  /// dérivé par les mêmes règles, pour que les 17 ambiances aient la même
  /// "vibrance" au lieu de 17 hex choisis à la main.
  ///
  /// Les teintes sont réparties autour du cercle chromatique pour éviter
  /// les quasi-doublons d'avant (festif / drôle / évangélique étaient trois
  /// jaunes voisins ; énergique / motivant / voyage / romantique / colère,
  /// cinq rouge-orangés). Les moods "éteints" (sombre, nostalgique, triste,
  /// sommeil) gardent volontairement une saturation basse.
  static const Map<MoodType, (double, double, double)> _hsl = {
    MoodType.angry: (0, 0.85, 0.54),
    MoodType.energetic: (15, 0.95, 0.58),
    MoodType.motivating: (32, 0.95, 0.52),
    MoodType.evangelical: (40, 0.72, 0.64),
    MoodType.funny: (52, 0.98, 0.55),
    MoodType.nostalgic: (28, 0.34, 0.56),
    MoodType.concentration: (150, 0.85, 0.42),
    MoodType.spiritual: (176, 0.42, 0.62),
    MoodType.chill: (192, 0.98, 0.42),
    MoodType.sad: (208, 0.36, 0.50),
    MoodType.sleep: (224, 0.45, 0.60),
    MoodType.classical: (244, 0.58, 0.70),
    MoodType.dark: (262, 0.12, 0.54),
    MoodType.melancholic: (272, 0.62, 0.62),
    MoodType.festive: (296, 0.75, 0.60),
    MoodType.romantic: (342, 0.80, 0.58),
    // "roadtrip" : coucher de soleil, entre l'orange et le rose.
    MoodType.roadtrip: (6, 0.80, 0.60),
  };

  static final Map<MoodType?, MoodColors> _cache = {};

  /// Get colors for a specific mood
  static MoodColors forMood(MoodType? mood) {
    return _cache.putIfAbsent(mood, () => _build(mood));
  }

  static MoodColors _build(MoodType? mood) {
    final hsl = mood == null ? null : _hsl[mood];
    if (hsl == null) {
      // Inconnu : violet de la marque.
      return const MoodColors(
        primary: Color(0xFF7C6CFF),
        secondary: Color(0xFFA78BFA),
        gradientStart: Color(0xFF120F24),
        gradientEnd: Color(0xFF0A0A0A),
        glow: Color(0x667C6CFF),
        cardBg: Color(0xFF120F24),
      );
    }
    final (h, s, l) = hsl;
    Color at(double hue, double sat, double light) => HSLColor.fromAHSL(
          1,
          hue % 360,
          sat.clamp(0.0, 1.0),
          light.clamp(0.0, 1.0),
        ).toColor();

    final primary = at(h, s, l);
    return MoodColors(
      primary: primary,
      secondary: at(h + 22, s * 0.9, l + 0.05),
      gradientStart: at(h, s * 0.65, 0.065),
      gradientEnd: const Color(0xFF0A0A0A),
      glow: primary.withValues(alpha: 0.4),
      cardBg: at(h, s * 0.55, 0.08),
    );
  }

  /// Get linear gradient for background
  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          gradientStart,
          gradientEnd,
        ],
      );

  /// Get radial gradient for glow effects
  RadialGradient glowGradient({double radius = 0.5}) => RadialGradient(
        center: Alignment.center,
        radius: radius,
        colors: [
          glow,
          Colors.transparent,
        ],
      );
}

/// Extension to get MoodColors from MoodType
extension MoodTypeColors on MoodType {
  MoodColors get colors => MoodColors.forMood(this);
}
