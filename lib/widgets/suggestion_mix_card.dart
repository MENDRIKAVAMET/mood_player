import 'package:flutter/material.dart';

import '../models/track.dart';
import '../providers/mood_suggestions_provider.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import 'track_artwork.dart';

/// Couleur d'un mix : celle de l'ambiance la plus présente parmi ses
/// morceaux (ou la couleur principale de l'app si aucun n'est classé).
extension TrackMixTint on TrackMix {
  Color get tint {
    final counts = <MoodType, int>{};
    for (final t in tracks) {
      final m = t.mood;
      if (m != null && m != MoodType.unknown) {
        counts[m] = (counts[m] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return AppTheme.accentPrimary;
    final best =
        counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return MoodColors.forMood(best).primary;
  }
}

/// Carte d'un mix dans les carrousels de Découvertes : collage 2x2 des
/// pochettes sur un fond aux couleurs du mix, pastille « nombre de
/// morceaux », bouton lecture lumineux, nom du mix et artistes présents.
class SuggestionMixCard extends StatelessWidget {
  final TrackMix mix;
  final VoidCallback onTap;

  const SuggestionMixCard({super.key, required this.mix, required this.onTap});

  static const double _size = 148;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final covers = mix.tracks.take(4).toList();
    final tint = mix.tint;
    final cell = (_size - _gap) / 2;
    final radius = BorderRadius.circular(AppTheme.radiusL);

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
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: tint.withValues(alpha: 0.32),
                    blurRadius: 20,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Fond de secours si le mix a moins de 4 pochettes.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            tint.withValues(alpha: 0.7),
                            AppTheme.backgroundCard,
                          ],
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: _gap,
                      runSpacing: _gap,
                      children: [
                        for (final t in covers)
                          TrackArtwork(
                            track: t,
                            size: cell,
                            radius: 0,
                            placeholderFontSize: 22,
                          ),
                      ],
                    ),
                    // Voile en bas : garde le bouton et la pastille lisibles.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.28),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppTheme.spacingS,
                      top: AppTheme.spacingS,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Text(
                          '${mix.tracks.length} titres',
                          style: AppTheme.bodySmall.copyWith(
                            fontSize: 10.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: AppTheme.spacingS,
                      bottom: AppTheme.spacingS,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              tint,
                              Color.lerp(tint, AppTheme.brandBottom, 0.45)!,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tint.withValues(alpha: 0.55),
                              blurRadius: 12,
                              spreadRadius: -1,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 22),
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
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              mix.artistsSummary,
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
