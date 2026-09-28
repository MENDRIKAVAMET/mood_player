import 'dart:io';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Extract dominant colors from images using palette_generator
class ColorExtractor {
  /// Extract dominant color from an image URL
  static Future<Color?> extractDominantColor(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      // La pochette est le plus souvent un fichier local extrait des tags
      // du morceau, pas une URL. NetworkImage échouait dessus en silence,
      // et le lecteur retombait sur sa couleur par défaut.
      final ImageProvider provider =
          imageUrl.startsWith('http://') || imageUrl.startsWith('https://')
              ? NetworkImage(imageUrl)
              : FileImage(File(imageUrl));

      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(200, 200),
        maximumColorCount: 10,
      );

      return palette.dominantColor?.color ?? palette.vibrantColor?.color;
    } catch (e) {
      debugPrint('Error extracting color: $e');
      return null;
    }
  }

  /// Extract a color palette from an image URL
  static Future<PaletteColors> extractPalette(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const PaletteColors();
    }

    try {
      // La pochette est le plus souvent un fichier local extrait des tags
      // du morceau, pas une URL. NetworkImage échouait dessus en silence,
      // et le lecteur retombait sur sa couleur par défaut.
      final ImageProvider provider =
          imageUrl.startsWith('http://') || imageUrl.startsWith('https://')
              ? NetworkImage(imageUrl)
              : FileImage(File(imageUrl));

      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(200, 200),
        maximumColorCount: 10,
      );

      return PaletteColors(
        dominant: palette.dominantColor?.color,
        vibrant: palette.vibrantColor?.color,
        darkVibrant: palette.darkVibrantColor?.color,
        lightVibrant: palette.lightVibrantColor?.color,
        muted: palette.mutedColor?.color,
        darkMuted: palette.darkMutedColor?.color,
        lightMuted: palette.lightMutedColor?.color,
      );
    } catch (e) {
      debugPrint('Error extracting palette: $e');
      return const PaletteColors();
    }
  }

  /// Generate gradient colors from an image
  static Future<List<Color>> extractGradientColors(String? imageUrl) async {
    final palette = await extractPalette(imageUrl);

    return [
      palette.vibrant ?? palette.dominant ?? Colors.deepPurple,
      palette.darkVibrant ?? palette.darkMuted ?? const Color(0xFF121212),
    ];
  }
}

/// Container for extracted palette colors
class PaletteColors {
  final Color? dominant;
  final Color? vibrant;
  final Color? darkVibrant;
  final Color? lightVibrant;
  final Color? muted;
  final Color? darkMuted;
  final Color? lightMuted;

  const PaletteColors({
    this.dominant,
    this.vibrant,
    this.darkVibrant,
    this.lightVibrant,
    this.muted,
    this.darkMuted,
    this.lightMuted,
  });

  /// Get the best color for background (prefer dark variants)
  Color get backgroundColor =>
      darkVibrant ?? darkMuted ?? dominant ?? const Color(0xFF121212);

  /// Get the best color for accent
  Color get accentColor => vibrant ?? dominant ?? const Color(0xFF7C6CFF);

  /// Get gradient colors
  List<Color> get gradientColors => [
    backgroundColor,
    Color.lerp(backgroundColor, Colors.black, 0.5) ?? Colors.black,
  ];
}
