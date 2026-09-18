import 'dart:io';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';

/// Affiche la pochette d'un morceau.
///
/// `coverUrl` peut être deux choses très différentes : un chemin de
/// fichier local (pochette extraite des tags par [ArtworkService]) ou une
/// URL http. Les écrans utilisaient `Image.network` dans tous les cas, ce
/// qui échouait silencieusement sur les chemins locaux. Ce widget tranche
/// une fois pour toutes, et retombe sur un dégradé d'ambiance quand le
/// morceau n'a pas de pochette.
class TrackArtwork extends StatelessWidget {
  final Track track;
  final double size;
  final double radius;

  /// Taille de l'emoji d'ambiance affiché à défaut de pochette.
  final double? placeholderFontSize;

  const TrackArtwork({
    super.key,
    required this.track,
    required this.size,
    required this.radius,
    this.placeholderFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    final cover = track.coverUrl;

    if (cover != null && cover.isNotEmpty) {
      if (cover.startsWith('http://') || cover.startsWith('https://')) {
        return Image.network(
          cover,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(),
        );
      }

      // Chemin local. Le fichier peut avoir été purgé du cache entre-temps
      // (nettoyage système), d'où le errorBuilder plutôt qu'un test
      // d'existence synchrone qui bloquerait le build.
      return Image.file(
        File(cover),
        fit: BoxFit.cover,
        // Évite de décoder une image 512px pour une vignette de 56px.
        cacheWidth: (size * 3).round().clamp(64, 1024),
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    final moodColors = MoodColors.forMood(track.mood);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            moodColors.primary.withValues(alpha: 0.45),
            moodColors.secondary.withValues(alpha: 0.15),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          track.mood?.iconData ?? Icons.music_note_rounded,
          size: placeholderFontSize ?? size * 0.4,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Variante plein cadre, pour le grand lecteur où la pochette occupe tout
/// l'espace disponible au lieu d'un carré de taille fixe.
class TrackArtworkFill extends StatelessWidget {
  final Track track;
  final double radius;

  const TrackArtworkFill({
    super.key,
    required this.track,
    this.radius = AppTheme.radiusXL,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide.isFinite
            ? constraints.biggest.shortestSide
            : 320.0;
        return TrackArtwork(
          track: track,
          size: side,
          radius: radius,
          placeholderFontSize: side * 0.3,
        );
      },
    );
  }
}
