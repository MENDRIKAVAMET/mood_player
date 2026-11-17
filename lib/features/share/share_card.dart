import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';

/// Pochette du morceau sous forme d'[ImageProvider] (réseau ou fichier).
ImageProvider? shareCoverProvider(Track track) {
  final cover = track.coverUrl;
  if (cover == null || cover.isEmpty) return null;
  if (cover.startsWith('http://') || cover.startsWith('https://')) {
    return NetworkImage(cover);
  }
  return FileImage(File(cover));
}

/// Image choisie par l'utilisateur (réduite à 1080 px de large).
ImageProvider? shareCustomProvider(String? path) {
  if (path == null) return null;
  return ResizeImage(FileImage(File(path)), width: 1080);
}

/// Fond d'une carte de partage : image choisie > pochette floutée avec
/// pochette au centre > image du mood > dégradé du mood.
class ShareCardBackground extends StatelessWidget {
  final Track track;
  final ImageProvider? custom;
  final ImageProvider? cover;

  /// Affiche la pochette au centre par-dessus le fond flouté. À désactiver
  /// quand du texte occupe le centre de la carte.
  final bool showCoverInCenter;

  const ShareCardBackground({
    super.key,
    required this.track,
    required this.custom,
    required this.cover,
    this.showCoverInCenter = true,
  });

  Widget _gradient(MoodColors c) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.secondary, c.primary, c.gradientEnd],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = MoodColors.forMood(track.mood);
    final fallback = _gradient(c);
    final custom = this.custom;
    if (custom != null) {
      // Image choisie : plein cadre, sans pochette au centre.
      return Image(
        image: custom,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    final cover = this.cover;
    if (cover != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: Transform.scale(
              scale: 1.2,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Image(
                  image: cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
              ),
            ),
          ),
          if (showCoverInCenter)
            Align(
              alignment: const Alignment(0, -0.2),
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image(
                    image: cover,
                    fit: BoxFit.cover,
                    width: 250,
                    height: 250,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    final asset = track.mood?.imageAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}

/// Carte 9:16 (360 x 640) avec les paroles choisies, exportée en PNG.
/// [lines] : une entrée par ligne ; une chaîne vide marque un saut de strophe.
class LyricsImageCard extends StatelessWidget {
  final Track track;
  final List<String> lines;
  final ImageProvider? custom;
  final ImageProvider? cover;

  const LyricsImageCard({
    super.key,
    required this.track,
    required this.lines,
    required this.custom,
    required this.cover,
  });

  @override
  Widget build(BuildContext context) {
    const shadow = [
      Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 2)),
    ];
    return SizedBox(
      width: 360,
      height: 640,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ShareCardBackground(
              track: track,
              custom: custom,
              cover: cover,
              showCoverInCenter: false,
            ),
            // Voile sombre sur toute la carte : le texte doit rester lisible
            // quelle que soit l'image de fond.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.6),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                  stops: const [0, 0.35, 0.7, 1],
                ),
              ),
            ),
            Positioned(
              left: 24,
              top: 28,
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq_rounded,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Aura',
                    style: AppTheme.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            // Zone des paroles : si la sélection est longue, le texte
            // rétrécit pour tenir au lieu de déborder.
            Positioned(
              left: 28,
              right: 28,
              top: 76,
              bottom: 130,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 304,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines)
                          line.trim().isEmpty
                              ? const SizedBox(height: 18)
                              : Text(
                                  line,
                                  style: AppTheme.headlineLarge.copyWith(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                    shadows: shadow,
                                  ),
                                ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 28,
              right: 28,
              bottom: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headlineLarge.copyWith(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyLarge.copyWith(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
