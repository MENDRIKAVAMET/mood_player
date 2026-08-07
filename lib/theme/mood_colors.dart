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
      case MoodType.unknown:
      default:
        return const MoodColors(
          primary: Color(0xFF1DB954),
          secondary: Color(0xFF1ED760),
          gradientStart: Color(0xFF0A1508),
          gradientEnd: Color(0xFF0A0A0A),
          glow: Color(0x661DB954),
          cardBg: Color(0xFF0A1508),
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
