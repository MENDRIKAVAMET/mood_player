import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/mood_icons.dart';
import '../models/custom_mood.dart';
import 'custom_mood_image_view.dart';

/// Card for a user-created [CustomMood] on the home screen, styled like
/// [MoodCard] but using the mood's own emoji/color instead of a built-in
/// [MoodType]'s.
class CustomMoodCard extends ConsumerWidget {
  final CustomMood mood;
  final VoidCallback onTap;

  /// Appui long : utilisé pour changer l'image du mood.
  final VoidCallback? onLongPress;

  const CustomMoodCard({
    super.key,
    required this.mood,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(mood.colorValue);
    // Icône sombre sur les couleurs claires, blanche sur les foncées.
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light
            ? Colors.black87
            : Colors.white;

    // Image choisie par l'utilisateur (de l'app ou importée), s'il y en a une.
    final hasImage = CustomMoodImageView.hasImage(ref, mood.id);

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
              color.withValues(alpha: 0.55),
              color.withValues(alpha: 0.2),
              AppTheme.backgroundCard,
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 26,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Image plein cadre sous un voile sombre teinté de la couleur
            // du mood (même rendu que les cartes d'ambiance).
            if (hasImage) ...[
              Positioned.fill(child: CustomMoodImageView(moodId: mood.id)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: 0.18),
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
                    colors: [color.withValues(alpha: 0.3), Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(AppTheme.radiusM),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 14,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        MoodIcons.iconDataForKey(mood.icon),
                        size: 26,
                        color: onColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    mood.name,
                    style: AppTheme.titleLarge.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    '${mood.trackCount} morceau${mood.trackCount > 1 ? 'x' : ''}',
                    style: AppTheme.bodySmall.copyWith(
                      color: hasImage ? Colors.white.withValues(alpha: 0.85) : color,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: AppTheme.spacingL,
              right: AppTheme.spacingL,
              child: Container(
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
            ),
          ],
        ),
      ),
    );
  }
}

/// "+" card at the end of the custom moods row, to create a new one.
class CreateMoodCard extends StatelessWidget {
  final VoidCallback onTap;

  const CreateMoodCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accentPrimary.withValues(alpha: 0.16),
              AppTheme.backgroundCard,
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: AppTheme.accentPrimary.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentPrimary.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              'Créer\nun mood',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
