import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_mood_image.dart';
import '../providers/custom_mood_image_provider.dart';

/// Image d'un mood créé par l'utilisateur : une image de l'app ou une image
/// importée. N'affiche rien s'il n'a pas d'image (le parent garde alors son
/// dégradé de couleur) : voir [hasImage].
class CustomMoodImageView extends ConsumerWidget {
  final int moodId;

  /// Largeur de décodage, pour ne pas charger une image pleine taille
  /// dans une petite vignette.
  final int cacheWidth;

  const CustomMoodImageView({
    super.key,
    required this.moodId,
    this.cacheWidth = 600,
  });

  /// Vrai si ce mood a une image à afficher.
  static bool hasImage(WidgetRef ref, int moodId) {
    final image = ref.watch(customMoodImageProvider.select((m) => m[moodId]));
    return switch (image?.kind ?? CustomMoodImageKind.none) {
      CustomMoodImageKind.none => false,
      CustomMoodImageKind.asset => image?.assetPath != null,
      CustomMoodImageKind.custom => image?.customPath != null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(customMoodImageProvider.select((m) => m[moodId]));
    const empty = SizedBox.shrink();

    switch (image?.kind ?? CustomMoodImageKind.none) {
      case CustomMoodImageKind.none:
        return empty;
      case CustomMoodImageKind.asset:
        final asset = image?.assetPath;
        if (asset == null) return empty;
        return Image.asset(
          asset,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => empty,
        );
      case CustomMoodImageKind.custom:
        final path = image?.customPath;
        if (path == null) return empty;
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => empty,
        );
    }
  }
}
