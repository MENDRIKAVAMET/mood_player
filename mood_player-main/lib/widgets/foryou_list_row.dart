import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/app_theme.dart';
import 'track_artwork.dart';

/// Ligne compacte pour les sections « en liste » de Pour vous
/// (Les plus écoutés / Tes morceaux aimés) : petite pochette carrée,
/// titre + artiste, bouton lecture circulaire à droite.
///
/// Volontairement plus sobre que [TrackTile] — pas de liseré d'accent, pas
/// de pastille de mood, pas de menu ⋮ — ces sections sont un aperçu
/// scrollable, pas la bibliothèque complète.
class ForYouListRow extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  /// Libellé optionnel sous la pochette (ex. « 12 écoutes »), affiché en
  /// petit badge superposé au coin, comme le compteur d'écoutes des
  /// captures de référence.
  final String? badge;

  const ForYouListRow({
    super.key,
    required this.track,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
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
                if (badge != null)
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
            const SizedBox(width: AppTheme.spacingS),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.textTertiary.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: AppTheme.textSecondary,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
