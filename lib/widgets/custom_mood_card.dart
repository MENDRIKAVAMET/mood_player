import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/custom_mood.dart';

/// Card for a user-created [CustomMood] on the home screen, styled like
/// [MoodCard] but using the mood's own emoji/color instead of a built-in
/// [MoodType]'s.
class CustomMoodCard extends StatelessWidget {
  final CustomMood mood;
  final VoidCallback onTap;

  const CustomMoodCard({
    super.key,
    required this.mood,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(mood.colorValue);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 180,
        margin: const EdgeInsets.only(right: AppTheme.spacingM),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.1),
              AppTheme.backgroundCard,
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
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
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusM),
                    ),
                    child: Center(
                      child: Text(mood.icon, style: const TextStyle(fontSize: 28)),
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
                    style: AppTheme.bodySmall.copyWith(color: color),
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
        width: 120,
        height: 180,
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
