import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';
import '../../models/track.dart';
import '../../widgets/track_tile.dart';
import '../player/player_screen.dart';

/// Detailed mood screen showing all tracks for a specific mood
class MoodDetailScreen extends StatelessWidget {
  final MoodType mood;
  final List<Track> tracks;

  const MoodDetailScreen({
    super.key,
    required this.mood,
    required this.tracks,
  });

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(mood);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              moodColors.gradientStart,
              moodColors.gradientEnd,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(context, moodColors),

              // Mood info
              _buildMoodInfo(moodColors),

              const SizedBox(height: AppTheme.spacingL),

              // Track count
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingXL,
                ),
                child: Row(
                  children: [
                    Text(
                      '${tracks.length} morceau${tracks.length > 1 ? 'x' : ''}',
                      style: AppTheme.bodyLarge.copyWith(
                        color: moodColors.primary,
                      ),
                    ),
                    const Spacer(),
                    // Play all button
                    if (tracks.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlayerScreen(
                                track: tracks.first,
                                tracks: tracks,
                                initialIndex: 0,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingL,
                            vertical: AppTheme.spacingS,
                          ),
                          decoration: BoxDecoration(
                            color: moodColors.primary,
                            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: AppTheme.textInverse,
                                size: 20,
                              ),
                              const SizedBox(width: AppTheme.spacingXS),
                              Text(
                                'Tout lire',
                                style: AppTheme.labelLarge.copyWith(
                                  color: AppTheme.textInverse,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingL),

              // Track list
              Expanded(
                child: tracks.isEmpty
                    ? _buildEmptyState(moodColors)
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          bottom: AppTheme.spacingXXXL,
                        ),
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return TrackTile(
                            track: track,
                            index: index,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PlayerScreen(
                                    track: track,
                                    tracks: tracks,
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                            onPlay: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PlayerScreen(
                                    track: track,
                                    tracks: tracks,
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(
            duration: AppTheme.animSlow,
          ),
    );
  }

  Widget _buildHeader(BuildContext context, MoodColors moodColors) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.backgroundCardElevated.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          // Title
          Expanded(
            child: Text(
              mood.displayName,
              style: AppTheme.headlineLarge,
            ),
          ),
          // Mood icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: moodColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            child: Center(
              child: Icon(
                mood.iconData,
                size: 24,
                color: moodColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodInfo(MoodColors moodColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingXL,
      ),
      child: Row(
        children: [
          // Color indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: moodColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ambiance ${mood.displayName}',
                style: AppTheme.titleLarge.copyWith(
                  color: moodColors.primary,
                ),
              ),
              Text(
                _getMoodDescription(mood),
                style: AppTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(MoodColors moodColors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: moodColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                mood.iconData,
                size: 36,
                color: moodColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingL),
          Text(
            'Aucun morceau',
            style: AppTheme.headlineMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Ajoutez des morceaux pour cette ambiance',
            style: AppTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _getMoodDescription(MoodType mood) {
    switch (mood) {
      case MoodType.energetic:
        return 'Musique dynamique et entraînante';
      case MoodType.chill:
        return 'Moments de détente et de calme';
      case MoodType.melancholic:
        return 'Émotions profondes et nostalgiques';
      case MoodType.festive:
        return 'Ambiance de fête et de joie';
      case MoodType.romantic:
        return 'Moments tendres et intimes';
      case MoodType.concentration:
        return 'Focus et productivité';
      case MoodType.motivating:
        return 'Inspiration et motivation';
      case MoodType.sad:
        return 'Mélancolie et réflexion';
      case MoodType.unknown:
        return 'Découvrir cette ambiance';
    }
  }
}
