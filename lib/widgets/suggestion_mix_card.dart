import 'package:flutter/material.dart';

import '../providers/mood_suggestions_provider.dart';
import '../theme/app_theme.dart';
import 'track_artwork.dart';

/// Carte d'un mix de suggestions dans le carrousel horizontal de « Pour
/// vous » : collage 2x2 des pochettes, nom du mix, artistes présents.
class SuggestionMixCard extends StatelessWidget {
  final SuggestionMix mix;
  final VoidCallback onTap;

  const SuggestionMixCard({super.key, required this.mix, required this.onTap});

  static const double _size = 148;

  @override
  Widget build(BuildContext context) {
    final covers = mix.tracks.take(4).toList();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _size,
        margin: const EdgeInsets.only(right: AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                boxShadow: AppTheme.shadowSmall,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Wrap(
                      children: [
                        for (final t in covers)
                          TrackArtwork(
                            track: t,
                            size: _size / 2,
                            radius: 0,
                            placeholderFontSize: 22,
                          ),
                      ],
                    ),
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
                          ),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              mix.title,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${mix.tracks.length} morceaux · ${mix.artistsSummary}',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
