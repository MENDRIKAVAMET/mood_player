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
                    style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
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
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: color.withValues(alpha: 0.6),
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
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: AppTheme.textTertiary.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, color: AppTheme.accentPrimary),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Créer\nun mood',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
