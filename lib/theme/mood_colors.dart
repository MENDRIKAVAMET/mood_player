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

  /// Get colors for a specific mood
  static MoodColors forMood(MoodType? mood) {
    switch (mood) {
      case MoodType.energetic:
        return const MoodColors(
          primary: Color(0xFFFF6B35),
          secondary: Color(0xFFFF9F1C),
          gradientStart: Color(0xFF1A0F00),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66FF6B35),
          cardBg: Color(0xFF1A1008),
        );
      case MoodType.chill:
        return const MoodColors(
          primary: Color(0xFF00B4D8),
          secondary: Color(0xFF0077B6),
          gradientStart: Color(0xFF001524),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x6600B4D8),
          cardBg: Color(0xFF081A24),
        );
      case MoodType.melancholic:
        return const MoodColors(
          primary: Color(0xFF7B2CBF),
          secondary: Color(0xFF9D4EDD),
          gradientStart: Color(0xFF100820),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x667B2CBF),
          cardBg: Color(0xFF120A20),
        );
      case MoodType.festive:
        return const MoodColors(
          primary: Color(0xFFFFD166),
          secondary: Color(0xFFEF476F),
          gradientStart: Color(0xFF1A1508),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66FFD166),
          cardBg: Color(0xFF1A1208),
        );
      case MoodType.romantic:
        return const MoodColors(
          primary: Color(0xFFE63946),
          secondary: Color(0xFFFF6B6B),
          gradientStart: Color(0xFF1A0810),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66E63946),
          cardBg: Color(0xFF1A0810),
        );
      case MoodType.concentration:
        return const MoodColors(
          primary: Color(0xFF06D6A0),
          secondary: Color(0xFF118AB2),
          gradientStart: Color(0xFF081A14),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x6606D6A0),
          cardBg: Color(0xFF081A14),
        );
      case MoodType.motivating:
        return const MoodColors(
          primary: Color(0xFFFF6D00),
          secondary: Color(0xFFFFAB00),
          gradientStart: Color(0xFF1A1000),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66FF6D00),
          cardBg: Color(0xFF1A1000),
        );
      case MoodType.sad:
        return const MoodColors(
          primary: Color(0xFF457B9D),
          secondary: Color(0xFF1D3557),
          gradientStart: Color(0xFF0A1020),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66457B9D),
          cardBg: Color(0xFF0A1420),
        );
      case MoodType.evangelical:
        return const MoodColors(
          primary: Color(0xFFF4C95D),
          secondary: Color(0xFFFFFFFF),
          gradientStart: Color(0xFF1A1608),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66F4C95D),
          cardBg: Color(0xFF1A1608),
        );
      case MoodType.angry:
        return const MoodColors(
          primary: Color(0xFFD00000),
          secondary: Color(0xFF9D0208),
          gradientStart: Color(0xFF200404),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66D00000),
          cardBg: Color(0xFF1A0606),
        );
      case MoodType.nostalgic:
        return const MoodColors(
          primary: Color(0xFFB08968),
          secondary: Color(0xFFDDB892),
          gradientStart: Color(0xFF1C140C),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66B08968),
          cardBg: Color(0xFF1C140C),
        );
      case MoodType.dark:
        return const MoodColors(
          primary: Color(0xFF6B6B7B),
          secondary: Color(0xFF4A4E69),
          gradientStart: Color(0xFF0E0E14),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x666B6B7B),
          cardBg: Color(0xFF0E0E14),
        );
      case MoodType.sleep:
        return const MoodColors(
          primary: Color(0xFF3D5A80),
          secondary: Color(0xFF98C1D9),
          gradientStart: Color(0xFF0A121C),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x663D5A80),
          cardBg: Color(0xFF0A121C),
        );
      case MoodType.funny:
        return const MoodColors(
          primary: Color(0xFFFFC300),
          secondary: Color(0xFFFF6F91),
          gradientStart: Color(0xFF1E1808),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66FFC300),
          cardBg: Color(0xFF1E1808),
        );
      case MoodType.roadtrip:
        return const MoodColors(
          primary: Color(0xFFEE6C4D),
          secondary: Color(0xFFF4A261),
          gradientStart: Color(0xFF1C0F08),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66EE6C4D),
          cardBg: Color(0xFF1C0F08),
        );
      case MoodType.spiritual:
        return const MoodColors(
          primary: Color(0xFF83C5BE),
          secondary: Color(0xFF52796F),
          gradientStart: Color(0xFF0A1614),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x6683C5BE),
          cardBg: Color(0xFF0A1614),
        );
      case MoodType.classical:
        return const MoodColors(
          primary: Color(0xFFD4A373),
          secondary: Color(0xFFE9C46A),
          gradientStart: Color(0xFF1C1408),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x66D4A373),
          cardBg: Color(0xFF1C1408),
        );
      case MoodType.unknown:
      default:
        return const MoodColors(
          primary: Color(0xFF7C6CFF),
          secondary: Color(0xFFA78BFA),
          gradientStart: Color(0xFF120F24),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x667C6CFF),
          cardBg: Color(0xFF120F24),
        );
    }
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
