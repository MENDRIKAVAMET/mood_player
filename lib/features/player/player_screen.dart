import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/audio_handler.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';
import 'queue_screen.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final Track track;
  final List<Track>? tracks;
  final int? initialIndex;

  const PlayerScreen({
    super.key,
    required this.track,
    this.tracks,
    this.initialIndex,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _isLiked = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  bool _shuffleMode = false;

  @override
  void initState() {
    super.initState();
    _playTrack();
    // Listen to repeat and shuffle mode changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audioHandlerAsync = ref.read(audioHandlerProvider);
      audioHandlerAsync.whenData((handler) {
        _repeatMode = handler.repeatMode;
        _shuffleMode = handler.shuffleMode;
        handler.repeatModeStream.listen((mode) {
          if (mounted) {
            setState(() {
              _repeatMode = mode;
            });
          }
        });
        handler.shuffleModeStream.listen((shuffle) {
          if (mounted) {
            setState(() {
              _shuffleMode = shuffle;
            });
          }
        });
      });
    });
  }

  Future<void> _playTrack() async {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) async {
      if (widget.tracks != null && widget.initialIndex != null) {
        // Play with queue context - replace queue
        await handler.playTrackFromList(widget.tracks!, widget.initialIndex!);
      } else {
        // Check if there's an existing queue
        final currentQueue = handler.queue.value;
        if (currentQueue.isNotEmpty) {
          // Find current track in queue and just play it
          final index = currentQueue.indexWhere(
            (item) => item.id == widget.track.id.toString(),
          );
          if (index >= 0) {
            await handler.skipToQueueItem(index);
          } else {
            // Track not in queue, add and play
            await handler.addAndPlayTrack(widget.track);
          }
        } else {
          // No queue, just play single track
          await handler.addAndPlayTrack(widget.track);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(widget.track.mood);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(currentPositionProvider);
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    
    // Extract dynamic colors from cover art if available
    final coverColorsAsync = ref.watch(coverColorProvider(widget.track.coverUrl));
    final paletteColors = coverColorsAsync.valueOrNull;
    
    // Use extracted colors if available, otherwise fall back to mood colors
    final dynamicGradientStart = paletteColors?.darkVibrant ?? moodColors.gradientStart;
    final dynamicGradientEnd = paletteColors?.darkMuted ?? moodColors.gradientEnd;
    final dynamicGlow = paletteColors?.vibrant ?? moodColors.glow;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              dynamicGradientStart,
              dynamicGradientEnd,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with back button and menu
              _buildHeader(moodColors),

              // Main player content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacingL),
                      // Cover art with glow
                      _buildCoverArt(moodColors, dynamicGlow),
                      const SizedBox(height: AppTheme.spacingXXL),
                      // Track info
                      _buildTrackInfo(moodColors),
                      const SizedBox(height: AppTheme.spacingXL),
                      // Progress bar
                      _buildProgressBar(moodColors, position, duration),
                      const SizedBox(height: AppTheme.spacingL),
                      // Controls
                      _buildControls(moodColors, isPlaying),
                      const SizedBox(height: AppTheme.spacingXL),
                      // Mood info card
                      if (widget.track.isClassified)
                        _buildMoodInfoCard(moodColors),
                      const SizedBox(height: AppTheme.spacingXXXL),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(MoodColors moodColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingM,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.backgroundCardElevated.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 24,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          // Playing from info
          Column(
            children: [
              Text(
                'En lecture',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textTertiary,
                ),
              ),
              Text(
                widget.track.moodDisplayName,
                style: AppTheme.labelMedium.copyWith(
                  color: moodColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          // More options
          GestureDetector(
            onTap: () => _showOptionsSheet(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.backgroundCardElevated.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.more_vert_rounded,
                size: 20,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt(MoodColors moodColors, Color dynamicGlow) {
    return Hero(
      tag: 'album_art_${widget.track.id}',
      child: Container(
        width: 280,
        height: 280,
        margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXL),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          boxShadow: [
            // Color glow shadow - dynamic from cover art
            BoxShadow(
              color: dynamicGlow,
              blurRadius: 60,
              spreadRadius: -8,
              offset: const Offset(0, 16),
            ),
            // Standard shadow
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
          image: widget.track.coverUrl != null
              ? DecorationImage(
                  image: NetworkImage(widget.track.coverUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: widget.track.coverUrl == null
            ? Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      moodColors.primary.withOpacity(0.3),
                      moodColors.secondary.withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                ),
                child: Center(
                  child: Text(
                    widget.track.mood?.icon ?? '🎵',
                    style: const TextStyle(fontSize: 80),
                  ),
                ),
              )
            : null,
      ),
    ).animate().scale(
          duration: AppTheme.animVerySlow,
          curve: Curves.easeOutBack,
        );
  }

  Widget _buildTrackInfo(MoodColors moodColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXXL),
      child: Column(
        children: [
          // Title
          Text(
            widget.track.title,
            style: AppTheme.headlineLarge.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 200),
              ),
          const SizedBox(height: AppTheme.spacingS),
          // Artist
          Text(
            widget.track.artist,
            style: AppTheme.titleMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 300),
              ),
          // Album
          if (widget.track.album != null) ...[
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              widget.track.album!,
              style: AppTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppTheme.spacingL),
          // Like button
          GestureDetector(
            onTap: () {
              setState(() {
                _isLiked = !_isLiked;
              });
            },
            child: AnimatedContainer(
              duration: AppTheme.animNormal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingL,
                vertical: AppTheme.spacingS,
              ),
              decoration: BoxDecoration(
                color: _isLiked
                    ? moodColors.primary.withOpacity(0.2)
                    : AppTheme.backgroundCardElevated,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                border: Border.all(
                  color: _isLiked
                      ? moodColors.primary.withOpacity(0.3)
                      : AppTheme.border.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isLiked ? moodColors.primary : AppTheme.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  Text(
                    _isLiked ? 'Aimé' : 'Aimer',
                    style: AppTheme.labelMedium.copyWith(
                      color: _isLiked ? moodColors.primary : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 400),
              ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(MoodColors moodColors, Duration position, Duration duration) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXXL),
      child: Column(
        children: [
          // Slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: moodColors.primary,
              inactiveTrackColor: moodColors.primary.withOpacity(0.2),
              thumbColor: moodColors.primary,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 7,
                elevation: 4,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 16,
              ),
              overlayColor: moodColors.primary.withOpacity(0.2),
              trackHeight: 4,
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: position.inSeconds.toDouble().clamp(
                    0.0,
                    duration.inSeconds.toDouble(),
                  ),
              max: duration.inSeconds.toDouble() > 0
                  ? duration.inSeconds.toDouble()
                  : 1,
              onChanged: (value) {
                _seekTo(Duration(seconds: value.toInt()));
              },
            ),
          ),
          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingS),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(MoodColors moodColors, bool isPlaying) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXXXL),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Shuffle
          _buildShuffleButton(moodColors),
          // Previous track
          _buildControlButton(
            icon: Icons.skip_previous_rounded,
            size: 32,
            onTap: () {
              _skipToPrevious();
            },
          ),
          // Play/Pause (main button)
          _buildPlayButton(moodColors, isPlaying),
          // Next track
          _buildControlButton(
            icon: Icons.skip_next_rounded,
            size: 32,
            onTap: () {
              _skipToNext();
            },
          ),
          // Repeat
          _buildRepeatButton(moodColors),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: size,
        color: AppTheme.textSecondary,
      ),
    );
  }

  Widget _buildPlayButton(MoodColors moodColors, bool isPlaying) {
    return GestureDetector(
      onTap: () {
        _togglePlayPause(isPlaying);
      },
      child: AnimatedContainer(
        duration: AppTheme.animNormal,
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppTheme.textPrimary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: moodColors.primary.withOpacity(0.3),
              blurRadius: 24,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: AppTheme.backgroundPrimary,
          size: 40,
        ),
      ),
    ).animate(onPlay: (controller) => isPlaying ? controller.repeat(reverse: true) : controller.stop())
      .scale(
        duration: const Duration(milliseconds: 200),
        begin: const Offset(1, 1),
        end: const Offset(1.02, 1.02),
      );
  }

  void _togglePlayPause(bool isPlaying) {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      if (isPlaying) {
        handler.pause();
      } else {
        handler.play();
      }
    });
  }

  void _seekTo(Duration position) {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.seek(position);
    });
  }

  void _skipToPrevious() {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.skipToPrevious();
    });
  }

  void _skipToNext() {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.skipToNext();
    });
  }

  void _cycleRepeatMode() {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.cycleRepeatMode();
    });
  }

  void _toggleShuffle() {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.toggleShuffle();
    });
  }

  Widget _buildShuffleButton(MoodColors moodColors) {
    final color = _shuffleMode ? moodColors.primary : AppTheme.textSecondary;
    
    return GestureDetector(
      onTap: _toggleShuffle,
      child: Icon(
        Icons.shuffle_rounded,
        size: 24,
        color: color,
      ),
    );
  }

  Widget _buildRepeatButton(MoodColors moodColors) {
    final isActive = _repeatMode != PlayerRepeatMode.off;
    final color = isActive ? moodColors.primary : AppTheme.textSecondary;
    
    return GestureDetector(
      onTap: _cycleRepeatMode,
      child: Icon(
        _repeatMode == PlayerRepeatMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        size: 24,
        color: color,
      ),
    );
  }

  Widget _buildMoodInfoCard(MoodColors moodColors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXXL),
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            moodColors.primary.withOpacity(0.15),
            moodColors.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(
          color: moodColors.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: moodColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            child: Center(
              child: Text(
                widget.track.mood?.icon ?? '🎵',
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.track.moodDisplayName,
                  style: AppTheme.titleMedium.copyWith(
                    color: moodColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.track.moodConfidence != null) ...[
                  const SizedBox(height: AppTheme.spacingXXS),
                  Text(
                    'Confiance: ${(widget.track.moodConfidence! * 100).toStringAsFixed(0)}%',
                    style: AppTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
          duration: AppTheme.animSlow,
          delay: const Duration(milliseconds: 500),
        );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return duration.inHours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  void _showQueueScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QueueScreen(),
      ),
    );
  }

  void _showOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.backgroundSecondary,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXL),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: AppTheme.spacingM),
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text('Voir la file d\'attente', style: AppTheme.bodyLarge),
                onTap: () {
                  Navigator.pop(context);
                  _showQueueScreen();
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: Text('Ajouter à une playlist', style: AppTheme.bodyLarge),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: Text('Partager', style: AppTheme.bodyLarge),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: AppTheme.spacingM),
            ],
          ),
        ),
      ),
    );
  }
}
