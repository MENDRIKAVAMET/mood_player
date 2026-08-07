import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import '../models/track.dart';

/// Premium track tile for lists
class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final bool isPlaying;
  final int index;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onPlay,
    this.isPlaying = false,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(track.mood);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingL,
          vertical: AppTheme.spacingXS,
        ),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: isPlaying
              ? moodColors.primary.withOpacity(0.1)
              : AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: isPlaying
                ? moodColors.primary.withOpacity(0.3)
                : AppTheme.border.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Track number or playing indicator
            if (isPlaying)
              _buildPlayingIndicator(moodColors)
            else
              _buildTrackNumber(),

            const SizedBox(width: AppTheme.spacingM),

            // Album art
            _buildAlbumArt(moodColors),

            const SizedBox(width: AppTheme.spacingM),

            // Track info
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
                  const SizedBox(height: AppTheme.spacingXXS),
                  Row(
                    children: [
                      if (track.isClassified) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingS,
                            vertical: AppTheme.spacingXXS,
                          ),
                          decoration: BoxDecoration(
                            color: moodColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(AppTheme.radiusS),
                          ),
                          child: Text(
                            '${track.mood?.icon ?? ''} ${track.moodDisplayName}',
                            style: AppTheme.labelSmall.copyWith(
                              color: moodColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingS),
                      ],
                      Expanded(
                        child: Text(
                          track.artist,
                          style: AppTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Play button
            if (onPlay != null)
              GestureDetector(
                onTap: onPlay,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? moodColors.primary
                        : AppTheme.backgroundCardElevated,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: isPlaying
                        ? AppTheme.backgroundPrimary
                        : AppTheme.textPrimary,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ).animate().fadeIn(
            duration: AppTheme.animNormal,
            delay: Duration(milliseconds: 50 * index),
          ).slideY(
            begin: 0.02,
            end: 0,
            duration: AppTheme.animNormal,
            delay: Duration(milliseconds: 50 * index),
          ),
    );
  }

  Widget _buildTrackNumber() {
    return SizedBox(
      width: 24,
      child: Text(
        '${index + 1}',
        style: AppTheme.bodyMedium.copyWith(
          color: AppTheme.textTertiary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPlayingIndicator(MoodColors moodColors) {
    return SizedBox(
      width: 24,
      child: Icon(
        Icons.equalizer_rounded,
        color: moodColors.primary,
        size: 20,
      ),
    );
  }

  Widget _buildAlbumArt(MoodColors moodColors) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: moodColors.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        image: track.coverUrl != null
            ? DecorationImage(
                image: NetworkImage(track.coverUrl!),
                fit: BoxFit.cover,
              )
            : null,
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: moodColors.glow,
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: track.coverUrl == null
          ? Center(
              child: Text(
                track.mood?.icon ?? '🎵',
                style: const TextStyle(fontSize: 28),
              ),
            )
          : null,
    );
  }
}
