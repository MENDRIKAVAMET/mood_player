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

/// Panneau vitré en bas des cartes de partage (image et vidéo) : [top]
/// (paroles), puis pochette, titre et artiste. Un seul widget pour que la
/// carte image et la carte vidéo aient exactement la même forme.
class ShareGlassPanel extends StatelessWidget {
  final Track track;
  final ImageProvider? cover;

  /// Contenu au-dessus de la ligne pochette / titre (en général les paroles).
  final Widget? top;

  const ShareGlassPanel({
    super.key,
    required this.track,
    required this.cover,
    this.top,
  });

  Widget _artwork() {
    final c = cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 46,
        height: 46,
        child: c != null
            ? Image(
                image: c,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _artFallback(),
              )
            : _artFallback(),
      ),
    );
  }

  Widget _artFallback() => const ColoredBox(
        color: Color(0x33FFFFFF),
        child: Icon(Icons.music_note_rounded, color: Colors.white70),
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.24),
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.16),
              ],
              stops: const [0, 0.55, 1],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (top != null) ...[
                top!,
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  _artwork(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyLarge.copyWith(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyLarge.copyWith(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo Aura (haut gauche des cartes de partage).
class ShareAuraLogo extends StatelessWidget {
  const ShareAuraLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.graphic_eq_rounded, size: 18, color: Colors.white),
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
    );
  }
}

/// Carte 9:16 (360 x 640) avec les paroles choisies, exportée en PNG.
/// Même forme que la carte de la vidéo : image plein cadre, logo Aura en
/// haut à gauche, panneau vitré en bas (paroles en serif, pochette, titre,
/// artiste).
/// [lines] : une entrée par ligne (7 max) ; une chaîne vide marque un saut
/// de strophe.
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

  Widget _lyrics() {
    const style = TextStyle(
      fontFamily: 'serif',
      color: Colors.white,
      fontSize: 24,
      fontWeight: FontWeight.w500,
      height: 1.2,
      shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)],
    );
    // Si les lignes sont longues (retours à la ligne), le bloc rétrécit pour
    // tenir dans la carte au lieu de déborder.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 330),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 288,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                line.trim().isEmpty
                    ? const SizedBox(height: 14)
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(line.trim(), style: style),
                      ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            // Léger dégradé : garde le logo et le panneau lisibles.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  stops: const [0, 0.22, 0.6, 1],
                ),
              ),
            ),
            const Positioned(left: 24, top: 28, child: ShareAuraLogo()),
            Positioned(
              left: 16,
              right: 16,
              bottom: 36,
              child: ShareGlassPanel(
                track: track,
                cover: cover,
                top: lines.isEmpty ? null : _lyrics(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
