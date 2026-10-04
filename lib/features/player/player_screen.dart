import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/audio_handler.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_artwork.dart';
import '../../theme/mood_colors.dart';
import 'equalizer_screen.dart';
import 'queue_screen.dart';
import 'lyrics_screen.dart';
import '../../widgets/track_options_sheet.dart';
import '../../widgets/mood_edit_sheet.dart';

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

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin {
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  bool _shuffleMode = false;

  /// The track actually shown on screen. Starts as the track the user
  /// tapped, then follows whatever the audio handler is really playing
  /// (updated in build() below) so title/artist/cover stay in sync when
  /// skipping to next/previous.
  late Track _displayTrack = widget.track;

  /// Suivi du swipe par événements bruts (Listener) plutôt que par le
  /// système de gestes de Flutter : les boutons, le slider et la carte
  /// d'ambiance ne peuvent ainsi plus "voler" le geste quand les contrôles
  /// sont affichés. Seul le slider de progression est exclu (un drag dessus
  /// doit faire avancer la musique, pas changer de morceau).
  int? _swipePointer;
  bool _swipeIgnored = false;
  bool _pointerOnSlider = false;
  Axis? _swipeAxis;
  Offset _swipeDelta = Offset.zero;
  Offset _swipeBase = Offset.zero;

  /// Distance avant de considérer un mouvement comme un swipe (même valeur
  /// que le seuil de tap de Flutter, pour qu'un tap ne soit jamais pris pour
  /// un swipe ni l'inverse).
  static const double _swipeSlop = 18.0;

  /// Minimum distance (px) a drag needs to cover before it counts as a
  /// deliberate swipe rather than an accidental brush of the screen.
  static const double _swipeThreshold = 80.0;

  /// Live translation applied to the whole player content: follows the
  /// finger while dragging, then gets animated the rest of the way (either
  /// back to zero, or fully off-screen before completing the underlying
  /// navigation/skip) so next/prev/back/lyrics all feel like a real,
  /// physically-dragged page transition instead of an instant cut.
  Offset _contentOffset = Offset.zero;
  late final AnimationController _transitionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Animation<Offset>? _offsetAnimation;
  bool _isAnimatingTransition = false;

  /// Contrôle l'affichage des boutons/barre de progression par-dessus la
  /// pochette plein écran : visible à l'ouverture, se cache tout seul
  /// après [_hideDelay] d'inactivité, et un tap sur l'écran bascule l'état
  /// (le retoucher relance le minuteur, le recacher l'annule).
  bool _controlsVisible = true;
  Timer? _hideTimer;
  static const Duration _hideDelay = Duration(seconds: 3);

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    final onSlider = _pointerOnSlider;
    _pointerOnSlider = false;
    if (_swipePointer != null) return; // un seul doigt suivi
    _swipePointer = e.pointer;
    _swipeIgnored = onSlider || _isAnimatingTransition;
    _swipeAxis = null;
    _swipeDelta = Offset.zero;
    _swipeBase = Offset.zero;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _swipePointer || _swipeIgnored) return;
    _swipeDelta += e.delta;

    // Verrouille l'axe dès que le doigt a assez bougé : le contenu ne suit
    // plus que horizontalement OU verticalement (pas de diagonale bancale).
    if (_swipeAxis == null) {
      if (_swipeDelta.distance < _swipeSlop) return;
      _swipeAxis = _swipeDelta.dx.abs() > _swipeDelta.dy.abs()
          ? Axis.horizontal
          : Axis.vertical;
      _swipeBase = _swipeDelta; // évite un saut de 18px au démarrage
    }

    final moved = _swipeDelta - _swipeBase;
    setState(() {
      _contentOffset = _swipeAxis == Axis.horizontal
          ? Offset(moved.dx, 0)
          : Offset(0, moved.dy);
    });
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _swipePointer) return;
    final axis = _swipeAxis;
    final swiping = axis != null && !_swipeIgnored;
    _swipePointer = null;
    _swipeAxis = null;
    if (swiping) _finishSwipe(axis);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _swipePointer) return;
    final swiping = _swipeAxis != null && !_swipeIgnored;
    _swipePointer = null;
    _swipeAxis = null;
    if (swiping) _snapContentBack();
  }

  void _finishSwipe(Axis axis) {
    if (_isAnimatingTransition) return;
    final size = MediaQuery.of(context).size;

    if (axis == Axis.horizontal) {
      final dx = _contentOffset.dx;
      if (dx.abs() < _swipeThreshold) {
        _snapContentBack();
        return;
      }
      if (dx < 0) {
        // Swipe gauche -> paroles : le contenu finit de sortir de l'écran,
        // puis la page des paroles arrive depuis la droite.
        _runOffsetAnimation(
          target: Offset(-size.width, 0),
          curve: Curves.easeInCubic,
          onComplete: () {
            Navigator.of(context)
                .push(_buildSlideRoute(LyricsScreen(track: _displayTrack)))
                .then((_) => _resetContentOffset());
          },
        );
      } else {
        // Swipe droite -> retour à la liste.
        _animatedPop(direction: Offset(size.width, 0));
      }
    } else {
      final dy = _contentOffset.dy;
      if (dy.abs() < _swipeThreshold) {
        _snapContentBack();
        return;
      }
      // Swipe haut -> morceau suivant, swipe bas -> précédent.
      _slideToTrack(goingNext: dy < 0, size: size);
    }
  }

  /// Eases the dragged content back to its resting position - used when a
  /// drag didn't cross the swipe threshold.
  void _snapContentBack() {
    _runOffsetAnimation(target: Offset.zero, curve: Curves.easeOutCubic);
  }

  void _resetContentOffset() {
    if (mounted) setState(() => _contentOffset = Offset.zero);
  }

  /// Drives [_contentOffset] from its current value to [target] over the
  /// transition controller, optionally running [onComplete] once it lands -
  /// this is what makes both the cancelled (snap-back) and committed
  /// (finish leaving the screen) cases feel like one continuous gesture.
  Future<void> _runOffsetAnimation({
    required Offset target,
    required Curve curve,
    VoidCallback? onComplete,
  }) async {
    setState(() => _isAnimatingTransition = true);
    _offsetAnimation = Tween<Offset>(begin: _contentOffset, end: target).animate(
      CurvedAnimation(parent: _transitionController, curve: curve),
    );
    void listener() {
      setState(() => _contentOffset = _offsetAnimation!.value);
    }

    _offsetAnimation!.addListener(listener);
    await _transitionController.forward(from: 0);
    _offsetAnimation!.removeListener(listener);
    if (mounted) setState(() => _isAnimatingTransition = false);
    onComplete?.call();
  }

  /// Slides the whole player content off-screen (in [direction]) before
  /// popping, so the back gesture and the top-bar back button both get the
  /// same dragged-away transition instead of an instant pop.
  Future<void> _animatedPop({Offset? direction}) async {
    if (_isAnimatingTransition) return;
    final size = MediaQuery.of(context).size;
    // Default: slide down, matching the down-chevron back button. A swipe
    // to the right passes its own horizontal target instead.
    final target = direction ?? Offset(0, size.height);
    await _runOffsetAnimation(target: target, curve: Curves.easeInCubic);
    if (mounted) Navigator.of(context).pop();
  }

  /// Slides the current track's artwork/title out toward [goingNext]'s edge
  /// of the screen, performs the actual skip once it's off, then slides the
  /// (by then updated) content back in from the opposite edge - a manual
  /// version of the classic "next page" scroll transition, since next/prev
  /// stay on this same route rather than pushing a new one.
  Future<void> _slideToTrack({required bool goingNext, required Size size}) async {
    if (_isAnimatingTransition) return;
    final exitOffset = Offset(0, goingNext ? -size.height : size.height);
    await _runOffsetAnimation(target: exitOffset, curve: Curves.easeInCubic);

    if (goingNext) {
      _skipToNext();
    } else {
      _skipToPrevious();
    }

    // Position the (about to appear) next track just off the opposite edge,
    // then ease it in to zero - continuing the same motion the finger/tap
    // started rather than popping straight to the final frame.
    setState(() => _contentOffset = Offset(0, goingNext ? size.height : -size.height));
    await _runOffsetAnimation(target: Offset.zero, curve: Curves.easeOutCubic);
  }

  /// A push/pop transition where the new page slides in from the right and
  /// the current one slides out underneath it, matching the direction of
  /// the left-swipe that opens it.
  Route<T> _buildSlideRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final incoming = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        final outgoing = Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.25, 0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic));
        return SlideTransition(
          position: outgoing,
          child: SlideTransition(position: incoming, child: child),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _playTrack();
    _scheduleHide();
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    _transitionController.dispose();
    super.dispose();
  }

  Future<void> _playTrack() async {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.when(
      data: (handler) async {
        try {
          if (widget.tracks != null && widget.initialIndex != null) {
            // Play with queue context - replace queue
            await handler.playTrackFromList(widget.tracks!, widget.initialIndex!);
          } else {
            // If this is already the track that's currently loaded (e.g.
            // tapping the mini player to open the full player while a
            // song is mid-playback), don't touch the queue position at
            // all - skipToQueueItem() seeks back to 0, which is exactly
            // the "restarts from the beginning" bug. Just make sure it's
            // playing (in case it was paused) and leave position alone.
            final activeItem = handler.mediaItem.value;
            if (activeItem != null &&
                activeItem.id == _displayTrack.id.toString()) {
              if (!handler.playbackState.value.playing) {
                await handler.play();
              }
            } else {
              // Check if there's an existing queue
              final currentQueue = handler.queue.value;
              if (currentQueue.isNotEmpty) {
                // Find the tapped track in queue and just play it
                final index = currentQueue.indexWhere(
                  (item) => item.id == _displayTrack.id.toString(),
                );
                if (index >= 0) {
                  await handler.skipToQueueItem(index);
                } else {
                  // Track not in queue, add and play
                  await handler.addAndPlayTrack(_displayTrack);
                }
              } else {
                // No queue, just play single track
                await handler.addAndPlayTrack(_displayTrack);
              }
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Impossible de lire ce morceau : $e')),
            );
          }
        }
      },
      loading: () {
        // Audio service still starting up (e.g. very first launch): retry
        // once it's ready instead of silently doing nothing.
        ref.read(audioHandlerProvider.future).then((_) {
          if (mounted) _playTrack();
        });
      },
      error: (e, st) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lecteur audio indisponible : $e'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the displayed track in sync with whatever the audio handler is
    // really playing (changes on skip/next/previous), falling back to the
    // initially-tapped track if we can't resolve a match yet. Always watch
    // trackProvider (not just inside the id-mismatch branch) so this screen
    // also rebuilds when the *same* track's data changes in place - e.g.
    // its mood/confidence being edited from the sheet below.
    final knownTracks = ref.watch(trackProvider).tracks;
    final currentMediaItem = ref.watch(currentTrackProvider).valueOrNull;
    if (currentMediaItem != null && currentMediaItem.id != _displayTrack.id.toString()) {
      final matched = knownTracks.where((t) => t.id.toString() == currentMediaItem.id);
      if (matched.isNotEmpty) {
        _displayTrack = matched.first;
      }
    }

    final moodColors = MoodColors.forMood(_displayTrack.mood);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(currentPositionProvider);
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        // Swipes (next/prev/lyrics/back) : événements bruts, valables que
        // les boutons soient affichés ou non.
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: GestureDetector(
        // Un tap simple sur l'écran bascule l'affichage des boutons.
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: ClipRect(
          child: Transform.translate(
            offset: _contentOffset,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Pochette centrée à la largeur de l'écran, fond flou autour.
                TrackArtworkFitBlur(track: _displayTrack),
                // Voile sombre en haut et en bas pour que le titre et les
                // boutons restent lisibles quelle que soit la pochette.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.fromRGBO(0, 0, 0, 0.65),
                        Color.fromRGBO(0, 0, 0, 0.05),
                        Color.fromRGBO(0, 0, 0, 0.05),
                        Color.fromRGBO(0, 0, 0, 0.8),
                      ],
                      stops: [0, 0.28, 0.5, 1],
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      // Titre + artiste : toujours visibles, comme sur la
                      // référence. Seuls les boutons qui les entourent (retour,
                      // options) apparaissent/disparaissent avec les contrôles.
                      _buildTopBar(moodColors),
                      const Spacer(),
                      // Barre de progression + contrôles de lecture : se
                      // cachent en glissant vers le bas et en s'effaçant après
                      // 3s d'inactivité, ou dès qu'on retape sur l'écran.
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOut,
                        offset: _controlsVisible ? Offset.zero : const Offset(0, 0.12),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: _controlsVisible ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: AppTheme.spacingL),
                              child: Column(
                                children: [
                                  _buildLikeButton(moodColors),
                                  const SizedBox(height: AppTheme.spacingL),
                                  _buildProgressBar(moodColors, position, duration),
                                  const SizedBox(height: AppTheme.spacingL),
                                  _buildControls(moodColors, isPlaying),
                                  const SizedBox(height: AppTheme.spacingXL),
                                  if (_displayTrack.isClassified)
                                    _buildMoodInfoCard(moodColors),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Titre et artiste, toujours affichés. Le bouton retour à gauche et le
  /// bouton options à droite s'effacent avec le reste des contrôles - le
  /// texte central reste parfaitement en place puisque les deux côtés du
  /// [Row] gardent la même largeur, visibles ou non.
  Widget _buildTopBar(MoodColors moodColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingS,
        vertical: AppTheme.spacingM,
      ),
      child: Row(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _controlsVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: GestureDetector(
                onTap: () => _animatedPop(),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 26,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _displayTrack.title,
                  style: AppTheme.titleLarge.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _displayTrack.artist,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _controlsVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EqualizerScreen()),
                ),
                child: const SizedBox(
                  width: 44,
                  height: 48,
                  child: Icon(
                    Icons.equalizer_rounded,
                    size: 22,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _controlsVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: GestureDetector(
                onTap: () => _showOptionsSheet(),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 22,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLikeButton(MoodColors moodColors) {
    // Icône inchangée (26px) mais zone tactile de 44x44 centrée dessus, et
    // un petit retour haptique au like/unlike.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.mediumImpact();
        ref.read(trackProvider.notifier).toggleLike(_displayTrack);
        setState(() {});
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(
            _displayTrack.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _displayTrack.isLiked ? moodColors.primary : AppTheme.textPrimary,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(MoodColors moodColors, Duration position, Duration duration) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXXL),
      child: Column(
        children: [
          // Slider (exclu du swipe : un drag dessus = seek)
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _pointerOnSlider = true,
            child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: moodColors.primary,
              inactiveTrackColor: moodColors.primary.withValues(alpha: 0.2),
              thumbColor: moodColors.primary,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 7,
                elevation: 4,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 16,
              ),
              overlayColor: moodColors.primary.withValues(alpha: 0.2),
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
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXL),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Shuffle + répétition : un seul bouton qui fait défiler les
          // états (désactivé -> aléatoire -> répéter tout -> répéter un ->
          // désactivé) plutôt que deux boutons séparés.
          _buildShuffleRepeatButton(moodColors),
          Row(
            children: [
              // Previous track
              _buildControlButton(
                icon: Icons.skip_previous_rounded,
                size: 32,
                onTap: () {
                  _slideToTrack(goingNext: false, size: MediaQuery.of(context).size);
                },
              ),
              const SizedBox(width: AppTheme.spacingM),
              // Play/Pause (main button)
              _buildPlayButton(moodColors, isPlaying),
              const SizedBox(width: AppTheme.spacingM),
              // Next track
              _buildControlButton(
                icon: Icons.skip_next_rounded,
                size: 32,
                onTap: () {
                  _slideToTrack(goingNext: true, size: MediaQuery.of(context).size);
                },
              ),
            ],
          ),
          // File d'attente : tout à droite du groupe next/pause/prev.
          _buildQueueButton(moodColors),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
  }) {
    // Icône visuellement inchangée, mais zone tactile de 48x48 (taille
    // recommandée) centrée dessus - pas besoin de viser pile les 32px de
    // l'icône pour que le tap soit pris en compte.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Icon(
            icon,
            size: size,
            color: AppTheme.textSecondary,
          ),
        ),
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
              color: moodColors.primary.withValues(alpha: 0.3),
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
    HapticFeedback.lightImpact();
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

  /// Fait avancer le bouton fusionné shuffle/répétition d'un cran :
  /// désactivé -> aléatoire -> répéter tout -> répéter un -> désactivé.
  /// Un seul de ces trois états peut être actif à la fois, puisqu'ils
  /// partagent maintenant un seul bouton.
  void _cycleShuffleRepeat() {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      if (_shuffleMode) {
        handler.toggleShuffle();
        handler.setPlayerRepeatMode(PlayerRepeatMode.all);
      } else if (_repeatMode == PlayerRepeatMode.all) {
        handler.setPlayerRepeatMode(PlayerRepeatMode.one);
      } else if (_repeatMode == PlayerRepeatMode.one) {
        handler.setPlayerRepeatMode(PlayerRepeatMode.off);
      } else {
        handler.toggleShuffle();
      }
    });
  }

  Widget _buildShuffleRepeatButton(MoodColors moodColors) {
    final IconData icon;
    final bool active;
    if (_shuffleMode) {
      icon = Icons.shuffle_rounded;
      active = true;
    } else if (_repeatMode == PlayerRepeatMode.all) {
      icon = Icons.repeat_rounded;
      active = true;
    } else if (_repeatMode == PlayerRepeatMode.one) {
      icon = Icons.repeat_one_rounded;
      active = true;
    } else {
      icon = Icons.shuffle_rounded;
      active = false;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _cycleShuffleRepeat,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Icon(
            icon,
            size: 24,
            color: active ? moodColors.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildQueueButton(MoodColors moodColors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showQueueScreen,
      child: const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: 24,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMoodInfoCard(MoodColors moodColors) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusL),
      onTap: () => showMoodEditSheet(context, ref, _displayTrack),
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXXL),
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            moodColors.primary.withValues(alpha: 0.15),
            moodColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(
          color: moodColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: moodColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            child: Center(
              child: Icon(
                _displayTrack.mood?.iconData ?? Icons.music_note_rounded,
                size: 24,
                color: moodColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayTrack.moodDisplayName,
                  style: AppTheme.titleMedium.copyWith(
                    color: moodColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_displayTrack.moodConfidence != null) ...[
                  const SizedBox(height: AppTheme.spacingXXS),
                  Text(
                    'Confiance: ${(_displayTrack.moodConfidence! * 100).toStringAsFixed(0)}%',
                    style: AppTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.edit_rounded,
            size: 18,
            color: moodColors.primary.withValues(alpha: 0.6),
          ),
        ],
      ),
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
    showTrackOptionsSheet(
      context,
      ref,
      _displayTrack,
      onShowQueue: _showQueueScreen,
    );
  }
}
