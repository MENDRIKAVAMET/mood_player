import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers/audio_provider.dart'
    show currentTrackIdProvider, isPlayingProvider;
import '../theme/mood_colors.dart';
import '../theme/app_theme.dart';
import 'track_artwork.dart';
import 'track_tile.dart' show EqualizerIndicator;

/// Ligne compacte pour les sections « en liste » de Pour vous
/// (Les plus écoutés / Tes morceaux aimés) : petite pochette carrée,
/// titre + artiste, bouton lecture circulaire à droite.
///
/// Volontairement plus sobre que [TrackTile] — pas de liseré d'accent, pas
/// de pastille de mood, pas de menu ⋮ — ces sections sont un aperçu
/// scrollable, pas la bibliothèque complète.
class ForYouListRow extends ConsumerWidget {
  final Track track;
  final VoidCallback onTap;

  /// Bouton lecture/pause de droite : joue sans ouvrir le lecteur.
  final VoidCallback? onPlay;

  /// Libellé optionnel sous la pochette (ex. « 12 écoutes »), affiché en
  /// petit badge superposé au coin, comme le compteur d'écoutes des
  /// captures de référence.
  final String? badge;

  const ForYouListRow({
    super.key,
    required this.track,
    required this.onTap,
    this.onPlay,
    this.badge,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ligne du morceau en cours : même repère visuel que TrackTile
    // (fond teinté du mood, titre coloré, égaliseur animé, bouton pause).
    final isPlaying = ref.watch(
      currentTrackIdProvider.select((id) => id == track.id.toString()),
    );
    final accent = MoodColors.forMood(track.mood).primary;

    final audioPlaying = ref.watch(isPlayingProvider);
    final mood = track.mood;

    // Carte en verre ; le morceau en cours s'allume : bordure et halo de
    // la couleur de son mood, fond teinté, égaliseur animé sur la pochette.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingS + 2,
            vertical: AppTheme.spacingS,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isPlaying
                    ? accent.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.10),
                isPlaying
                    ? accent.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            border: Border.all(
              color: isPlaying
                  ? accent.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.12),
              width: isPlaying ? 1.5 : 1,
            ),
            boxShadow: isPlaying
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  TrackArtwork(
                    track: track,
                    size: 48,
                    radius: 12,
                    placeholderFontSize: 20,
                  ),
                  if (isPlaying)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: EqualizerIndicator(color: accent)),
                      ),
                    ),
                  if (badge != null && !isPlaying)
                    Positioned(
                      left: 2,
                      bottom: 2,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.headphones_rounded,
                                size: 9, color: Colors.white70),
                            const SizedBox(width: 2),
                            Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      style: AppTheme.bodyLarge.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // Point de couleur du mood (le nom du mood reste
                        // accessible dans l'onglet Ambiances et le lecteur).
                        if (mood != null) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            track.artist,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingS),
              GestureDetector(
                onTap: onPlay ?? onTap,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: isPlaying ? AppTheme.brandGradient : null,
                        color: isPlaying
                            ? null
                            : Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying && audioPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
