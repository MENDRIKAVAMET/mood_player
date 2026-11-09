import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import '../models/track.dart';
import 'mood_image.dart';

/// Premium mood card for the home screen
class MoodCard extends ConsumerWidget {
  final MoodType mood;
  final int trackCount;
  final VoidCallback onTap;

  /// Appui long : utilisé pour changer l'image de l'ambiance.
  final VoidCallback? onLongPress;

  const MoodCard({
    super.key,
    required this.mood,
    required this.trackCount,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moodColors = MoodColors.forMood(mood);
    // Icône noire sur les teintes claires (jaune, orange...), blanche sur
    // les autres : contraste lisible quelle que soit l'ambiance.
    final onPrimary =
        ThemeData.estimateBrightnessForColor(moodColors.primary) ==
                Brightness.light
            ? Colors.black87
            : Colors.white;

    // Image personnalisée par l'utilisateur, sinon celle d'origine.
    final hasImage = MoodImage.hasImage(ref, mood);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              moodColors.primary.withValues(alpha: 0.55),
              moodColors.secondary.withValues(alpha: 0.2),
              AppTheme.backgroundCard,
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: moodColors.primary.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: moodColors.primary.withValues(alpha: 0.5),
              blurRadius: 26,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Photo de l'ambiance : plein cadre, avec un voile sombre (plus
            // marqué en bas, sous le nom) teinté de la couleur du mood pour
            // garder le texte lisible et l'identité de chaque ambiance.
            if (hasImage) ...[
              Positioned.fill(
                child: MoodImage(mood: mood),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        moodColors.primary.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ],

            // Reflet « verre » discret en haut de la carte.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4],
                    ),
                  ),
                ),
              ),
            ),

            // Glow effect
            if (!hasImage)
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      moodColors.primary.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mood icon : pastille en dégradé, icône à fort contraste
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [moodColors.primary, moodColors.secondary],
                          ),
                          borderRadius: BorderRadius.circular(AppTheme.radiusM),
                          boxShadow: [
                            BoxShadow(
                              color: moodColors.primary.withValues(alpha: 0.5),
                              blurRadius: 14,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(mood.iconData, size: 26, color: onPrimary),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      // Compteur de morceaux : se réduit si la carte est
                      // étroite (plutôt que de déborder).
                      Flexible(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '$trackCount morceau${trackCount > 1 ? 'x' : ''}',
                            maxLines: 1,
                            style: AppTheme.bodySmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Nom de l'ambiance + pastille « ouvrir »
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          mood.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.titleLarge.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            height: 1.15,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_outward_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          ],
        ),
      ).animate().fadeIn(
            duration: AppTheme.animSlow,
          ).slideX(
            begin: 0.05,
            end: 0,
            duration: AppTheme.animSlow,
          ),
    );
  }
}
