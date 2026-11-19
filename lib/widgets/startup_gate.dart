import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/ui_gate.dart';
import '../theme/app_theme.dart';

/// Écran de démarrage de l'app : le scan d'abord, l'interface ensuite, et
/// l'utilisateur coincé sur l'écran de chargement tant que l'écran n'est pas
/// prêt.
///
/// Trois phases, dans l'ordre :
///  1. Le scan de la bibliothèque (appel natif MediaStore) déroule sous le
///     splash : l'app n'est pas encore construite, donc pas de concurrence
///     entre le scan et le build de l'interface (ça c'est ce qui faisait
///     ramer l'ouverture avant).
///  2. Le scan terminé, on construit l'app *derrière* le splash (le splash
///     reste en foreground et absorbe les touches). Les pochettes et images
///     se décodent pendant les premières frames, mais l'utilisateur ne peut
///     rien faire : il est encore sur l'écran de chargement.
///  3. Dès que l'écran est "apprêté" (première frame peinte + période
///     tranquille sans frame lente), on retire le splash et on laisse l'utilisateur
///     naviguer.
///
/// Un `await Future.delayed(5s)` n'était pas une bonne solution : trop long
/// sur un rapide, trop court sur un lent, et il ne mesurait rien à la charge
/// réelle de l'écran. Voir [_waitForScreenReady].
///
/// Garde-fous :
///  * durée minimale d'affichage ([_minSplash]) pour que l'écran ne clignote
///    pas quand le scan est instantané (rien de nouveau sur l'appareil) ;
///  * durée maximale ([_maxWait]) : si un appel natif se bloque, on entre
///    quand même dans l'app (le scan continue en arrière-plan) au lieu de
///    laisser l'utilisateur coincé sur le chargement ;
///  * [_waitForScreenReady] a son propre plafond (10 s) : si la mesure des
///    frames déraille sur un appareil étrange, on entre quand même dans l'app
///    au lieu de laisser l'utilisateur coincé indéfiniment.
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

  bool _appBuilt = false;
  bool _screenReady = false;
  Timer? _minTimer;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    if (widget.skipScan) {
      _appBuilt = true;
      _screenReady = true;
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
    setState(() => _appBuilt = true);

    // Attendre que la première frame de l'app soit peinte, puis que l'écran
    // soit tranquille (images décodées) avant de retirer le splash.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await UiGate.instance
          .idle(minGap: const Duration(milliseconds: 150))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Si le timeout se déclenche, on passe tout de même à l'app.
    }
    if (!mounted) return;
    setState(() => _screenReady = true);
  }


  @override
  void dispose() {
    _minTimer?.cancel();
    _safetyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si le scan n'est pas encore fini, on montre seulement le splash.
    if (!_appBuilt) {
      return const _StartupSplash(key: ValueKey('splash'));
    }
    // Le scan est fini, l'app est construite derrière le splash.
    // Tant que l'écran n'est pas encore prêt, on couvre l'app d'une couche
    // splash non interactive pour bloquer le scroll.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_screenReady)
          const Positioned.fill(
            child: _StartupSplash(key: ValueKey('splash')),
          ),
      ],
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
