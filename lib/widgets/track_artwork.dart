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

  Widget _placeholder() => _MoodPlaceholder(
        track: track,
        iconSize: placeholderFontSize ?? size * 0.4,
      );
}

/// Dégradé d'ambiance + icône, utilisé quand un morceau n'a pas de pochette
/// (ou que son fichier est introuvable).
class _MoodPlaceholder extends StatelessWidget {
  final Track track;
  final double iconSize;

  const _MoodPlaceholder({required this.track, required this.iconSize});

  @override
  Widget build(BuildContext context) {
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
          size: iconSize,
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

/// Pochette du grand lecteur : l'image est affichée nette, à la largeur de
/// l'écran et centrée verticalement (sans être étirée ni recadrée). L'espace
/// restant en haut et en bas est rempli par la même image, agrandie et
/// floutée.
class TrackArtworkFitBlur extends StatelessWidget {
  final Track track;

  const TrackArtworkFitBlur({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final cover = track.coverUrl;
    final placeholder = _MoodPlaceholder(
      track: track,
      iconSize: MediaQuery.sizeOf(context).width * 0.3,
    );

    if (cover == null || cover.isEmpty) {
      return SizedBox.expand(child: placeholder);
    }

    final pixelWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 2048);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fond : même image, en "cover", décodée en toute petite taille
        // (48px) puis agrandie avec un filtrage bilinéaire de qualité :
        // l'agrandissement donne lui-même le flou.
        //
        // Volontairement SANS ImageFilter.blur : un flou appliqué sur une
        // couche qui glisse (swipe suivant/précédent/paroles) laissait
        // des bandes floues verticales/horizontales au bord du contenu
        // déplacé, à cause du rendu des bords du filtre. Sans filtre, plus
        // d'artefact, et c'est aussi bien moins coûteux à animer.
        RepaintBoundary(
          child: _coverImage(
            cover,
            fit: BoxFit.cover,
            cacheWidth: 48,
            fallback: placeholder,
            filterQuality: FilterQuality.high,
          ),
        ),
        // Léger assombrissement du fond pour faire ressortir l'image nette.
        const ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.25)),
        // Pochette nette encadrée (coins arrondis, ombre portée), plus
        // grande qu'avant (marge 24 au lieu de 44), avec un flou latéral
        // qui démarre pile au bord du carré.
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const margin = 24.0;
              final side = constraints.maxWidth - margin * 2;
              if (side <= 0) return const SizedBox.shrink();

              // Flou de côté : la pochette (déjà décodée en 48px, donc
              // floue à l'agrandissement) est retournée en miroir et
              // collée contre chaque bord du carré. Les pixels voisins du
              // carré sont ainsi continus avec la pochette nette, puis le
              // flou s'estompe vers le fond. Pas d'ImageFilter.blur (voir
              // plus haut : artefacts pendant les swipes).
              Widget sideBlur({required bool left}) {
                return SizedBox(
                  width: margin,
                  height: side,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => LinearGradient(
                      begin: left ? Alignment.centerRight : Alignment.centerLeft,
                      end: left ? Alignment.centerLeft : Alignment.centerRight,
                      colors: const [Colors.white, Colors.transparent],
                    ).createShader(rect),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment:
                            left ? Alignment.centerRight : Alignment.centerLeft,
                        minWidth: side,
                        maxWidth: side,
                        minHeight: side,
                        maxHeight: side,
                        child: Transform.flip(
                          flipX: true,
                          child: SizedBox(
                            width: side,
                            height: side,
                            child: _coverImage(
                              cover,
                              fit: BoxFit.cover,
                              cacheWidth: 48,
                              fallback: placeholder,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  sideBlur(left: true),
                  SizedBox(
                    width: side,
                    height: side,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 32,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: _coverImage(
                          cover,
                          fit: BoxFit.cover,
                          cacheWidth: pixelWidth,
                          fallback: placeholder,
                        ),
                      ),
                    ),
                  ),
                  sideBlur(left: false),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _coverImage(
    String cover, {
    required BoxFit fit,
    required int cacheWidth,
    required Widget fallback,
    FilterQuality filterQuality = FilterQuality.low,
  }) {
    if (cover.startsWith('http://') || cover.startsWith('https://')) {
      return Image.network(
        cover,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cacheWidth,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Image.file(
      File(cover),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheWidth,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
