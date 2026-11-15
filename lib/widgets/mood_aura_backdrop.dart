import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../theme/mood_colors.dart';
import 'mood_image.dart';

/// Fond « aura » du grand lecteur : l'image de l'ambiance du morceau en
/// cours, très floue, qui dérive lentement, sous un lavis de la couleur de
/// l'ambiance. Change en fondu quand on passe à un morceau d'une autre
/// ambiance.
///
/// Suit le choix d'image de l'utilisateur (origine, animé, importée). Si
/// l'ambiance n'a pas d'image (ou si l'utilisateur a choisi « icône »), il
/// ne reste que le lavis de couleur.
///
/// Choix techniques, pour rester fluide pendant les swipes du lecteur :
///  * pas d'`ImageFilter.blur` (il laissait des bandes au bord du contenu
///    déplacé, voir `TrackArtworkFitBlur`) : l'image est décodée toute
///    petite puis agrandie en haute qualité, ce qui donne le flou ;
///  * l'image est dans un `RepaintBoundary` : pendant la dérive, seul un
///    déplacement/zoom de calque est rejoué, pas le dessin de l'image ;
///  * la dérive ne tourne que pendant la lecture, et s'arrête si l'appareil
///    demande de réduire les animations.
class MoodAuraBackdrop extends ConsumerStatefulWidget {
  final MoodType mood;

  /// Vrai pendant la lecture : l'image dérive. Faux : elle reste immobile.
  final bool animate;

  const MoodAuraBackdrop({
    super.key,
    required this.mood,
    this.animate = true,
  });

  @override
  ConsumerState<MoodAuraBackdrop> createState() => _MoodAuraBackdropState();
}

class _MoodAuraBackdropState extends ConsumerState<MoodAuraBackdrop>
    with SingleTickerProviderStateMixin {
  // Démarre au milieu de la course : à l'arrêt, l'image est centrée.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
    value: 0.5,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncDrift();
  }

  @override
  void didUpdateWidget(covariant MoodAuraBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDrift();
  }

  void _syncDrift() {
    final shouldRun = widget.animate && !_reduceMotion;
    if (shouldRun && !_drift.isAnimating) {
      _drift.repeat(reverse: true);
    } else if (!shouldRun && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 700),
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        child: _AuraLayer(
          key: ValueKey(widget.mood),
          mood: widget.mood,
          drift: _drift,
        ),
      ),
    );
  }
}

class _AuraLayer extends ConsumerWidget {
  final MoodType mood;
  final Animation<double> drift;

  const _AuraLayer({super.key, required this.mood, required this.drift});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = MoodColors.forMood(mood);
    final hasImage = MoodImage.hasImage(ref, mood);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            Opacity(
              opacity: 0.62,
              child: AnimatedBuilder(
                animation: drift,
                // L'image (et son RepaintBoundary) est construite une seule
                // fois : seule la transformation change à chaque image.
                child: RepaintBoundary(
                  child: MoodImage(
                    mood: mood,
                    cacheWidth: 64,
                    filterQuality: FilterQuality.high,
                    fallback: (_) => const SizedBox.shrink(),
                  ),
                ),
                builder: (context, child) {
                  final t = Curves.easeInOut.transform(drift.value);
                  return Transform.translate(
                    offset: Offset((t - 0.5) * 28, (0.5 - t) * 18),
                    child: Transform.scale(
                      scale: 1.14 + 0.06 * t,
                      child: child,
                    ),
                  );
                },
              ),
            ),
          // Lavis de la couleur de l'ambiance (plus présent quand il n'y a
          // pas d'image, pour que l'ambiance se voie quand même).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.primary.withValues(alpha: hasImage ? 0.35 : 0.55),
                  colors.secondary.withValues(alpha: hasImage ? 0.20 : 0.30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
