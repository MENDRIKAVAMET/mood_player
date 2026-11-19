import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// Écran de démarrage de l'app : tant que la bibliothèque n'est pas scannée,
/// on n'affiche que l'icône de l'app (grande, au centre, avec une animation
/// de chargement). Le scan se fait derrière ; l'app (le [child]) n'est
/// construite et affichée qu'une fois le scan terminé.
///
/// Pourquoi : lancer le scan pendant que la bibliothèque, les onglets et les
/// images se construisent en même temps faisait ramer l'ouverture. Ici, un
/// seul travail à la fois - le scan d'abord, l'interface ensuite.
///
/// Garde-fous :
///  * durée minimale d'affichage ([_minSplash]) pour que l'écran ne clignote
///    pas quand le scan est instantané (rien de nouveau sur l'appareil) ;
///  * durée maximale ([_maxWait]) : si un appel natif se bloque, on entre
///    quand même dans l'app (le scan continue en arrière-plan) au lieu de
///    laisser l'utilisateur coincé sur le chargement.
class StartupGate extends ConsumerStatefulWidget {
  final Widget child;

  /// Entre directement dans l'app sans scan ni écran de démarrage. Réservé
  /// aux tests : le scan passe par des plugins natifs (permissions,
  /// MediaStore) qui ne répondent jamais dans `flutter test`, ce qui
  /// laissait l'écran de démarrage affiché indéfiniment.
  final bool skipScan;

  const StartupGate({super.key, required this.child, this.skipScan = false});

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  static const Duration _minSplash = Duration(milliseconds: 800);
  static const Duration _maxWait = Duration(seconds: 45);

  bool _ready = false;
  Timer? _minTimer;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    if (widget.skipScan) {
      _ready = true;
      return;
    }
    // Après la première image : l'icône est déjà à l'écran quand le scan
    // démarre, il n'y a donc jamais d'écran vide pendant l'attente.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final minDone = Completer<void>();
    final scanDone = Completer<void>();

    _minTimer = Timer(_minSplash, () {
      if (!minDone.isCompleted) minDone.complete();
    });
    _safetyTimer = Timer(_maxWait, () {
      if (!scanDone.isCompleted) scanDone.complete();
    });

    // Le scan gère la permission, les erreurs, la reprise sur base locale.
    ref
        .read(trackProvider.notifier)
        .scanAndLoadTracks(showCachedWhileScanning: false)
        .catchError((Object _) {})
        .whenComplete(() {
      if (!scanDone.isCompleted) scanDone.complete();
    });

    // Attendre le temps minimum d'affichage et la fin du scan.
    await Future.wait([minDone.future, scanDone.future]);
    _safetyTimer?.cancel();
    if (!mounted) return;

    // Le scan est terminé : on construit l'app derrière le splash.
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _minTimer?.cancel();
    _safetyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _ready
          ? KeyedSubtree(
              key: const ValueKey('app'),
              child: widget.child,
            )
          : const _StartupSplash(key: ValueKey('splash')),
    );
  }
}

/// L'écran lui-même : grande icône au centre, halo qui respire, et un arc
/// qui tourne autour de l'icône pour montrer que ça travaille.
class _StartupSplash extends StatefulWidget {
  const _StartupSplash({super.key});

  @override
  State<_StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<_StartupSplash>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _spin.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Grande : environ la moitié de la plus petite dimension de l'écran.
    final iconSize =
        (math.min(media.size.width, media.size.height) * 0.5).clamp(160.0, 260.0);
    final ringSize = iconSize + 56;
    // Décodée à la taille affichée (et non en 1024 px) : bien moins de RAM.
    final cachePx = (iconSize * media.devicePixelRatio).round();

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
            ),
            child: SizedBox(
              width: ringSize,
              height: ringSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Halo qui respire derrière l'icône.
                  AnimatedBuilder(
                    animation: _breath,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(_breath.value);
                      return Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentPrimary
                                  .withValues(alpha: 0.16 + t * 0.16),
                              blurRadius: 72,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Transform.scale(
                          scale: 1.0 + t * 0.03,
                          child: child,
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(iconSize * 0.22),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: iconSize,
                        height: iconSize,
                        cacheWidth: cachePx,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  // Arc de chargement qui tourne autour de l'icône.
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size(ringSize, ringSize),
                      painter: _RingPainter(
                        progress: _spin,
                        color: AppTheme.accentPrimary,
                      ),
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
}

class _RingPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;

  _RingPainter({required this.progress, required this.color})
      : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    const sweep = math.pi * 1.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final center = size.center(Offset.zero);

    // Piste fixe, très discrète.
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: 0.12),
    );

    // Arc dégradé (queue transparente -> tête pleine) qui tourne.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress.value * math.pi * 2);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(
      rect,
      0,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: sweep,
          colors: [color.withValues(alpha: 0), color],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}
