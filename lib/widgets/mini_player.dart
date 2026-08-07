import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import '../models/track.dart';
import '../providers/providers.dart';
import '../features/player/player_screen.dart';

/// Persistent mini player bar that shows above bottom navigation
class MiniPlayer extends ConsumerWidget {
  final Track currentTrack;

  const MiniPlayer({
    super.key,
    required this.currentTrack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(currentPositionProvider);
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;

    final moodColors = MoodColors.forMood(currentTrack.mood);
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: () {
        // The audio handler already has the queue, PlayerScreen will use it
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PlayerScreen(track: currentTrack),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            transitionDuration: AppTheme.animPageTransition,
          ),
        );
      },
      child: Container(
        height: 68,
        margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingS,
        ),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCardElevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: moodColors.primary.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingM,
                ),
                child: Row(
                  children: [
                    // Album art with Hero
                    Hero(
                      tag: 'album_art_${currentTrack.id}',
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: moodColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppTheme.radiusM),
                          image: currentTrack.coverUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(currentTrack.coverUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: currentTrack.coverUrl == null
                            ? Center(
                                child: Text(
                                  currentTrack.mood?.icon ?? '🎵',
                                  style: const TextStyle(fontSize: 24),
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingM),

                    // Track info
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentTrack.title,
                            style: AppTheme.bodyLarge.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppTheme.spacingXXS),
                          Text(
                            currentTrack.artist,
                            style: AppTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause button
                    GestureDetector(
                      onTap: () {
                        final audioHandler = ref.read(audioHandlerProvider);
                        audioHandler.whenData((handler) {
                          if (isPlaying) {
                            handler.pause();
                          } else {
                            handler.play();
                          }
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.textPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: AppTheme.backgroundPrimary,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Progress bar
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(AppTheme.radiusL),
                bottomRight: Radius.circular(AppTheme.radiusL),
              ),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(moodColors.primary),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
