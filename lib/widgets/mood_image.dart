import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mood_image_choice.dart';
import '../models/track.dart';
import '../providers/mood_image_provider.dart';

/// Image d'une ambiance selon le choix de l'utilisateur : photo d'origine
/// (défaut), illustration d'animé, image importée, ou rien (icône seule).
/// Utilisé partout où la photo d'une ambiance est affichée, pour qu'un
/// changement soit visible immédiatement et de façon cohérente (cartes,
/// pochettes par défaut...).
class MoodImage extends ConsumerWidget {
  final MoodType mood;

  /// Largeur de décodage, pour ne pas charger une photo pleine taille
  /// dans une petite vignette.
  final int cacheWidth;

  /// Affiché quand il n'y a pas d'image (choix « icône » ou aucune image
  /// disponible).
  final WidgetBuilder? fallback;

  const MoodImage({
    super.key,
    required this.mood,
    this.cacheWidth = 600,
    this.fallback,
  });

  /// Vrai si [mood] affiche une image (et non juste son icône) avec le
  /// choix actuel de l'utilisateur.
  static bool hasImage(WidgetRef ref, MoodType mood) {
    final choice = ref.watch(moodImageProvider.select((m) => m[mood]));
    return switch (choice?.source ?? MoodImageSource.original) {
      MoodImageSource.icon => false,
      MoodImageSource.custom => true,
      MoodImageSource.anime =>
        mood.animeImageAsset != null || mood.imageAsset != null,
      MoodImageSource.original => mood.imageAsset != null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(moodImageProvider.select((m) => m[mood]));
    final source = choice?.source ?? MoodImageSource.original;

    Widget fallbackWidget(BuildContext context) =>
        fallback?.call(context) ?? const SizedBox.shrink();

    Widget assetImage(BuildContext context, String? asset) {
      if (asset == null) return fallbackWidget(context);
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (ctx, _, _) => fallbackWidget(ctx),
      );
    }

    switch (source) {
      case MoodImageSource.icon:
        return fallbackWidget(context);
      case MoodImageSource.custom:
        final path = choice?.customPath;
        if (path != null) {
          return Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            // Fichier disparu : retour à l'image d'origine.
            errorBuilder: (ctx, _, _) => assetImage(ctx, mood.imageAsset),
          );
        }
        return assetImage(context, mood.imageAsset);
      case MoodImageSource.anime:
        return assetImage(context, mood.animeImageAsset ?? mood.imageAsset);
      case MoodImageSource.original:
        return assetImage(context, mood.imageAsset);
    }
  }
}
