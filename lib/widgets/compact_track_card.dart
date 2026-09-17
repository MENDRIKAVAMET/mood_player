import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';

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
    final moodColors = MoodColors.forMood(track.mood);

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
                    if (track.coverUrl != null)
                      Image.network(
                        track.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(moodColors),
                      )
                    else
                      _placeholder(moodColors),
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

  Widget _placeholder(MoodColors moodColors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            moodColors.primary.withValues(alpha: 0.4),
            moodColors.secondary.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          track.mood?.icon ?? '🎵',
          style: const TextStyle(fontSize: 36),
        ),
      ),
    );
  }
}
