import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import '../models/track.dart';

/// Premium mood card for the home screen
class MoodCard extends StatelessWidget {
  final MoodType mood;
  final int trackCount;
  final VoidCallback onTap;

  const MoodCard({
    super.key,
    required this.mood,
    required this.trackCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(mood);

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
              moodColors.primary.withOpacity(0.3),
              moodColors.primary.withOpacity(0.1),
              AppTheme.backgroundCard,
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: moodColors.primary.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: moodColors.glow,
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Glow effect
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
                      moodColors.primary.withOpacity(0.3),
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
                  // Mood icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: moodColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusM),
                    ),
                    child: Center(
                      child: Text(
                        mood.icon,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Mood name
                  Text(
                    mood.displayName,
                    style: AppTheme.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  // Track count
                  Text(
                    '$trackCount morceau${trackCount > 1 ? 'x' : ''}',
                    style: AppTheme.bodySmall.copyWith(
                      color: moodColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Arrow icon
            Positioned(
              bottom: AppTheme.spacingL,
              right: AppTheme.spacingL,
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: moodColors.primary.withOpacity(0.6),
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
