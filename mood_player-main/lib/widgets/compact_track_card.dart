import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/app_theme.dart';
import 'track_artwork.dart';

/// Carte compacte utilisée dans les carrousels horizontaux de « Pour vous ».
///
/// Format volontairement plus petit que [TrackTile] : ces sections sont là
/// pour donner un aperçu en un coup d'œil, pas pour remplacer la liste
/// complète — c'est justement ce qui poussait la bibliothèque hors de
/// l'écran avant la séparation en onglets.
class CompactTrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  /// Libellé facultatif affiché sous l'artiste (ex. « 12 écoutes »).
  final String? badge;

  const CompactTrackCard({
    super.key,
    required this.track,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 132,
        margin: const EdgeInsets.only(right: AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                boxShadow: AppTheme.shadowSmall,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TrackArtwork(
                      track: track,
                      size: 132,
                      radius: AppTheme.radiusM,
                      placeholderFontSize: 36,
                    ),
                    if (badge != null)
                      Positioned(
                        left: AppTheme.spacingS,
                        bottom: AppTheme.spacingS,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingS,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(AppTheme.radiusS),
                          ),
                          child: Text(
                            badge!,
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    // Médaillon lecture, plaqué à cheval sur le coin —
                    // même emplacement que les cartes "Recommandé" /
                    // "Dernier Ajout" de référence, plutôt qu'un badge
                    // texte seul.
                    Positioned(
                      right: AppTheme.spacingS,
                      bottom: AppTheme.spacingS,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.55),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              track.title,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textPrimary,
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
    );
  }
}
