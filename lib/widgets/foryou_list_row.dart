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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: Container(
        decoration: BoxDecoration(
          color: isPlaying ? accent.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingL,
            vertical: AppTheme.spacingXS,
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  TrackArtwork(
                    track: track,
                    size: 52,
                    radius: AppTheme.radiusS,
                    placeholderFontSize: 22,
                  ),
                  if (isPlaying)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(AppTheme.radiusS),
                        ),
                        child: Center(child: EqualizerIndicator(color: accent)),
                      ),
                    ),
                  if (badge != null && !isPlaying)
                    Positioned(
                      left: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                  children: [
                    Text(
                      track.title,
                      style: AppTheme.bodyLarge.copyWith(
                        color: isPlaying ? accent : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingS),
              GestureDetector(
                onTap: onPlay ?? onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPlaying
                            ? accent
                            : AppTheme.textTertiary.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      isPlaying && ref.watch(isPlayingProvider)
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                      color: isPlaying ? accent : AppTheme.textSecondary,
                      size: 18,
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
