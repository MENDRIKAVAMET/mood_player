import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'track_artwork.dart';
import '../theme/mood_colors.dart';
import '../models/track.dart';

/// Premium track tile for lists.
///
/// Signature "now playing" look: a soft mood-tinted wash with a slim
/// colored accent rail on the active row, a live animated equalizer in
/// place of the track number, and a glowing album cover — instead of a
/// generic boxed card repeated for every row.
class TrackTile extends StatefulWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onMore;
  final bool isPlaying;
  final int index;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onPlay,
    this.onMore,
    this.isPlaying = false,
    this.index = 0,
  });

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final isPlaying = widget.isPlaying;
    final moodColors = MoodColors.forMood(track.mood);

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: AppTheme.animFast,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: AppTheme.animNormal,
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingL,
            vertical: AppTheme.spacingXS,
          ),
          decoration: BoxDecoration(
            gradient: isPlaying
                ? LinearGradient(
                    colors: [
                      moodColors.primary.withValues(alpha: 0.18),
                      moodColors.primary.withValues(alpha: 0.04),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: isPlaying ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            border: Border.all(
              color: isPlaying
                  ? moodColors.primary.withValues(alpha: 0.35)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            // Surtout PAS CrossAxisAlignment.stretch ici. Dans une liste
            // (SliverList / ListView), la contrainte de hauteur reçue est
            // infinie ; `stretch` demande alors aux enfants une hauteur
            // tight de `constraints.maxHeight`, donc l'infini. En debug ça
            // lève « BoxConstraints forces an infinite height », et en
            // release la tuile se replie à zéro pixel : les morceaux sont
            // bien là, la liste a la bonne longueur, mais plus rien ne se
            // dessine. C'était exactement le bug — et ça expliquait aussi
            // pourquoi « Ajoutés récemment » s'affichait, lui : ses cartes
            // ne passent pas par cette Row.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Liseré d'accent — présent uniquement sur la piste active.
              // Hauteur explicite plutôt que `stretch`, pour la même raison.
              AnimatedContainer(
                duration: AppTheme.animNormal,
                width: isPlaying ? 3 : 0,
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
                decoration: BoxDecoration(
                  color: moodColors.primary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  boxShadow: isPlaying
                      ? [
                          BoxShadow(
                            color: moodColors.glow,
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(
                  left: AppTheme.spacingM,
                  right: AppTheme.spacingM,
                  top: AppTheme.spacingS,
                  bottom: AppTheme.spacingS,
                ),
                child: SizedBox(
                  width: 22,
                  child: Center(
                    child: isPlaying
                        ? _EqualizerIndicator(color: moodColors.primary)
                        : Text(
                            '${widget.index + 1}',
                            style: AppTheme.labelMedium.copyWith(
                              color: AppTheme.textTertiary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ),

              // Album art
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
                child: _AlbumArt(track: track, moodColors: moodColors, isPlaying: isPlaying),
              ),

              const SizedBox(width: AppTheme.spacingM),

              // Track info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: AppTheme.bodyLarge.copyWith(
                          color: isPlaying ? moodColors.primary : AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (track.isClassified) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacingS,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: moodColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppTheme.radiusS),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    track.mood?.iconData ?? Icons.music_note_rounded,
                                    size: 11,
                                    color: moodColors.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    track.moodDisplayName,
                                    style: AppTheme.labelSmall.copyWith(
                                      color: moodColors.primary,
                                    ),
                                  ),
                                ],
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
                          const SizedBox(width: AppTheme.spacingS),
                          Text(
                            track.durationFormatted,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textTertiary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Play button
              if (widget.onPlay != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppTheme.spacingS,
                    right: AppTheme.spacingS,
                  ),
                  child: Center(
                    child: GestureDetector(
                      onTap: widget.onPlay,
                      child: AnimatedContainer(
                        duration: AppTheme.animFast,
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: isPlaying
                              ? LinearGradient(
                                  colors: [moodColors.primary, moodColors.secondary],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isPlaying ? null : AppTheme.backgroundCardElevated,
                          shape: BoxShape.circle,
                          boxShadow: isPlaying
                              ? [
                                  BoxShadow(
                                    color: moodColors.glow,
                                    blurRadius: 14,
                                    spreadRadius: -2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: isPlaying ? AppTheme.backgroundPrimary : AppTheme.textPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),

              // Three-dot options button
              if (widget.onMore != null)
                GestureDetector(
                  onTap: widget.onMore,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingXS,
                      vertical: AppTheme.spacingS,
                    ),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final Track track;
  final MoodColors moodColors;
  final bool isPlaying;

  const _AlbumArt({
    required this.track,
    required this.moodColors,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: moodColors.glow,
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ]
            : AppTheme.shadowSmall,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: Stack(
          fit: StackFit.expand,
          children: [
            TrackArtwork(
              track: track,
              size: 56,
              radius: AppTheme.radiusM,
              placeholderFontSize: 24,
            ),

            // Subtle inner border for definition against dark backgrounds.
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Small live-looking equalizer made of three bars animating in a loop —
/// replaces the static icon so the currently playing row visibly breathes.
class _EqualizerIndicator extends StatefulWidget {
  final Color color;

  const _EqualizerIndicator({required this.color});

  @override
  State<_EqualizerIndicator> createState() => _EqualizerIndicatorState();
}

class _EqualizerIndicatorState extends State<_EqualizerIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Per-bar min/max height fractions and phase offsets for a natural,
  // non-synchronized bounce.
  static const List<List<double>> _bars = [
    [0.35, 1.0],
    [0.5, 0.75],
    [0.3, 0.9],
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_bars.length, (i) {
              final range = _bars[i];
              // Offset each bar's phase so they don't move in lockstep.
              final t = (_controller.value + i * 0.28) % 1.0;
              final wave = (1 - (2 * t - 1).abs());
              final heightFraction = range[0] + (range[1] - range[0]) * wave;
              return Container(
                width: 3,
                height: 16 * heightFraction,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
