import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/mood_colors.dart';

enum GhostEyes { dots, wide, happy, sleepy, hearts, narrow, sunglasses, wink }

enum GhostMouth { smile, grin, frown, flat, smirk, tinyO, tongue }

enum GhostBrows { none, angry, sad, determined }

enum GhostExtra { none, tear, blush, halo, zzz, confetti, notes, glasses }

/// L'expression du fantôme pour une ambiance : yeux, bouche, sourcils,
/// accessoire, rythme de flottement et petite phrase quand on le touche.
class GhostLook {
  final GhostEyes eyes;
  final GhostMouth mouth;
  final GhostBrows brows;
  final GhostExtra extra;

  /// Durée d'un va-et-vient en secondes. Doit diviser 12 (durée de la boucle
  /// d'animation) pour que le mouvement se raccorde sans saut.
  final int bobSeconds;

  /// Hauteur du flottement, en fraction de la largeur du fantôme.
  final double bobAmplitude;

  final String phrase;

  const GhostLook({
    required this.eyes,
    required this.mouth,
    required this.phrase,
    this.brows = GhostBrows.none,
    this.extra = GhostExtra.none,
    this.bobSeconds = 4,
    this.bobAmplitude = 0.03,
  });

  static const _neutral = GhostLook(
    eyes: GhostEyes.dots,
    mouth: GhostMouth.smile,
    phrase: 'Je n\'ai pas encore d\'avis…',
  );

  static GhostLook forMood(MoodType? mood) {
    if (mood == null) return _neutral;
    switch (mood) {
      case MoodType.unknown:
        return _neutral;
      case MoodType.energetic:
        return const GhostLook(
          eyes: GhostEyes.wide,
          mouth: GhostMouth.grin,
          bobSeconds: 2,
          bobAmplitude: 0.06,
          phrase: 'Ça bouge !',
        );
      case MoodType.chill:
        return const GhostLook(
          eyes: GhostEyes.happy,
          mouth: GhostMouth.smile,
          bobSeconds: 6,
          bobAmplitude: 0.035,
          phrase: 'On se détend…',
        );
      case MoodType.melancholic:
        return const GhostLook(
          eyes: GhostEyes.dots,
          mouth: GhostMouth.frown,
          brows: GhostBrows.sad,
          bobSeconds: 6,
          bobAmplitude: 0.025,
          phrase: 'Un peu de mélancolie…',
        );
      case MoodType.festive:
        return const GhostLook(
          eyes: GhostEyes.wide,
          mouth: GhostMouth.grin,
          extra: GhostExtra.confetti,
          bobSeconds: 2,
          bobAmplitude: 0.06,
          phrase: 'On fait la fête !',
        );
      case MoodType.romantic:
        return const GhostLook(
          eyes: GhostEyes.hearts,
          mouth: GhostMouth.smile,
          extra: GhostExtra.blush,
          phrase: 'Oh, mon cœur…',
        );
      case MoodType.concentration:
        return const GhostLook(
          eyes: GhostEyes.narrow,
          mouth: GhostMouth.flat,
          extra: GhostExtra.glasses,
          bobSeconds: 6,
          bobAmplitude: 0.015,
          phrase: 'Chut, je me concentre.',
        );
      case MoodType.motivating:
        return const GhostLook(
          eyes: GhostEyes.dots,
          mouth: GhostMouth.smile,
          brows: GhostBrows.determined,
          bobSeconds: 3,
          bobAmplitude: 0.05,
          phrase: 'Allez, on y va !',
        );
      case MoodType.sad:
        return const GhostLook(
          eyes: GhostEyes.dots,
          mouth: GhostMouth.frown,
          brows: GhostBrows.sad,
          extra: GhostExtra.tear,
          bobSeconds: 6,
          bobAmplitude: 0.02,
          phrase: 'Je suis là.',
        );
      case MoodType.evangelical:
        return const GhostLook(
          eyes: GhostEyes.happy,
          mouth: GhostMouth.smile,
          extra: GhostExtra.halo,
          bobSeconds: 6,
          bobAmplitude: 0.035,
          phrase: 'Paix et lumière.',
        );
      case MoodType.angry:
        return const GhostLook(
          eyes: GhostEyes.dots,
          mouth: GhostMouth.frown,
          brows: GhostBrows.angry,
          bobSeconds: 2,
          bobAmplitude: 0.04,
          phrase: 'Grrr !',
        );
      case MoodType.nostalgic:
        return const GhostLook(
          eyes: GhostEyes.happy,
          mouth: GhostMouth.smile,
          extra: GhostExtra.blush,
          bobSeconds: 6,
          phrase: 'Ça me rappelle des souvenirs…',
        );
      case MoodType.dark:
        return const GhostLook(
          eyes: GhostEyes.sleepy,
          mouth: GhostMouth.smirk,
          phrase: 'Côté obscur activé.',
        );
      case MoodType.sleep:
        return const GhostLook(
          eyes: GhostEyes.sleepy,
          mouth: GhostMouth.tinyO,
          extra: GhostExtra.zzz,
          bobSeconds: 6,
          bobAmplitude: 0.02,
          phrase: 'Zzz…',
        );
      case MoodType.funny:
        return const GhostLook(
          eyes: GhostEyes.wink,
          mouth: GhostMouth.tongue,
          bobSeconds: 3,
          bobAmplitude: 0.05,
          phrase: 'Hihi !',
        );
      case MoodType.roadtrip:
        return const GhostLook(
          eyes: GhostEyes.sunglasses,
          mouth: GhostMouth.smile,
          bobSeconds: 3,
          bobAmplitude: 0.04,
          phrase: 'En route !',
        );
      case MoodType.spiritual:
        return const GhostLook(
          eyes: GhostEyes.happy,
          mouth: GhostMouth.smile,
          extra: GhostExtra.halo,
          bobSeconds: 6,
          bobAmplitude: 0.035,
          phrase: 'Quelle sérénité…',
        );
      case MoodType.classical:
        return const GhostLook(
          eyes: GhostEyes.happy,
          mouth: GhostMouth.smile,
          extra: GhostExtra.notes,
          phrase: 'Bravo, maestro.',
        );
    }
  }
}

/// Petite mascotte qui flotte dans le lecteur : son visage suit l'ambiance
/// du morceau. Pendant la lecture elle flotte et cligne des yeux ; en
/// pause elle s'endort. Un tap la fait sautiller et affiche une phrase.
///
/// Dessinée entièrement en code (aucune image), aux couleurs de l'ambiance.
class MoodGhost extends StatefulWidget {
  final MoodType? mood;
  final bool playing;

  /// Largeur du fantôme ; la hauteur totale est 1,4 fois plus grande.
  final double size;

  const MoodGhost({
    super.key,
    required this.mood,
    required this.playing,
    this.size = 72,
  });

  @override
  State<MoodGhost> createState() => _MoodGhostState();
}

class _MoodGhostState extends State<MoodGhost> with TickerProviderStateMixin {
  /// Boucle de 12 s : flottement, clignements et accessoires en dérivent.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  /// Petit saut quand l'ambiance change ou quand on touche le fantôme.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  Timer? _bubbleTimer;
  bool _bubble = false;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _loop.repeat();
  }

  @override
  void didUpdateWidget(MoodGhost old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      if (widget.playing) {
        _loop.repeat();
      } else {
        _loop.stop();
      }
    }
    if (old.mood != widget.mood) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _loop.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _onTap() {
    _pop.forward(from: 0);
    setState(() => _bubble = true);
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _bubble = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = GhostLook.forMood(widget.mood);
    final color = MoodColors.forMood(widget.mood).primary;
    final size = widget.size;

    return SizedBox(
      width: size,
      height: size * 1.4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Semantics(
            button: true,
            label: 'Fantôme d\'humeur',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              child: AnimatedBuilder(
                animation: Listenable.merge([_loop, _pop]),
                builder: (context, _) {
                  final scale = 1 + 0.18 * math.sin(math.pi * _pop.value);
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.bottomCenter,
                    child: CustomPaint(
                      size: Size(size, size * 1.4),
                      painter: _GhostPainter(
                        look: look,
                        color: color,
                        t: _loop.value,
                        playing: widget.playing,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_bubble)
            Positioned(
              right: size + 6,
              top: size * 0.3,
              child: _SpeechBubble(text: look.phrase),
            ),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String text;
  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1B1530),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  final GhostLook look;
  final Color color;

  /// Avancement de la boucle de 12 s (0 à 1).
  final double t;
  final bool playing;

  const _GhostPainter({
    required this.look,
    required this.color,
    required this.t,
    required this.playing,
  });

  static const _ink = Color(0xFF1B1530);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final bodyH = w * 1.12;
    final bodyTop = w * 0.2;

    final cycles = 12 / look.bobSeconds;
    final s = math.sin(2 * math.pi * t * cycles);
    final lift = look.bobAmplitude * w * (0.5 + 0.5 * s);
    final frac = (t * cycles) % 1.0;

    // Ombre au sol : plus petite quand le fantôme monte.
    final shadowScale = 1 - 0.25 * (lift / (look.bobAmplitude * w + 0.0001));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, bodyTop + bodyH + w * 0.05),
        width: w * 0.62 * shadowScale,
        height: w * 0.08,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );

    canvas.save();
    canvas.translate(0, -lift);

    final body = _bodyPath(w, bodyH, bodyTop);
    canvas.drawPath(
      body,
      Paint()
        ..color = color.withValues(alpha: playing ? 0.55 : 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.12),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(Colors.white, color, 0.12)!,
            Color.lerp(Colors.white, color, playing ? 0.5 : 0.3)!,
          ],
        ).createShader(Rect.fromLTWH(0, bodyTop, w, bodyH)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.5),
    );

    _paintFace(canvas, w, bodyTop);
    _paintExtra(canvas, w, bodyTop, frac);
    canvas.restore();
  }

  Path _bodyPath(double w, double bodyH, double top) {
    final hemY = top + bodyH * 0.88;
    final bottom = top + bodyH;
    final path = Path()
      ..moveTo(0, hemY)
      ..lineTo(0, top + w / 2)
      ..arcTo(Rect.fromLTWH(0, top, w, w), math.pi, math.pi, false)
      ..lineTo(w, hemY);
    final seg = w / 3;
    for (var i = 0; i < 3; i++) {
      final x0 = w - i * seg;
      final x1 = x0 - seg;
      final down = i.isEven;
      path.quadraticBezierTo(
        (x0 + x1) / 2,
        down ? bottom + bodyH * 0.12 : top + bodyH * 0.70,
        x1,
        hemY,
      );
    }
    return path..close();
  }

  // ---------------------------------------------------------------------
  // Visage
  // ---------------------------------------------------------------------

  void _paintFace(Canvas canvas, double w, double top) {
    final ex1 = w * 0.34;
    final ex2 = w * 0.66;
    final ey = top + w * 0.46;
    final cx = w * 0.5;
    final my = top + w * 0.66;

    // En pause : le fantôme s'endort.
    final eyes = playing
        ? look.eyes
        : (look.eyes == GhostEyes.sunglasses
            ? GhostEyes.sunglasses
            : GhostEyes.sleepy);
    final mouth = playing
        ? look.mouth
        : (look.mouth == GhostMouth.frown ? GhostMouth.frown : GhostMouth.tinyO);
    final brows = playing ? look.brows : GhostBrows.none;

    final blink = playing &&
        ((t > 0.30 && t < 0.315) || (t > 0.80 && t < 0.815));
    final eyeScaleY = blink ? 0.1 : 1.0;

    final fill = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.032
      ..strokeCap = StrokeCap.round;

    void ovalEye(double x, double rx, double ry) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, ey),
          width: rx * 2,
          height: ry * 2 * eyeScaleY,
        ),
        fill,
      );
    }

    switch (eyes) {
      case GhostEyes.dots:
        ovalEye(ex1, w * 0.06, w * 0.075);
        ovalEye(ex2, w * 0.06, w * 0.075);
      case GhostEyes.wide:
        ovalEye(ex1, w * 0.085, w * 0.105);
        ovalEye(ex2, w * 0.085, w * 0.105);
        if (!blink) {
          final glint = Paint()..color = Colors.white;
          canvas.drawCircle(Offset(ex1 + w * 0.02, ey - w * 0.03), w * 0.022, glint);
          canvas.drawCircle(Offset(ex2 + w * 0.02, ey - w * 0.03), w * 0.022, glint);
        }
      case GhostEyes.happy:
        for (final x in [ex1, ex2]) {
          canvas.drawArc(
            Rect.fromCenter(
                center: Offset(x, ey + w * 0.02), width: w * 0.15, height: w * 0.15),
            math.pi,
            math.pi,
            false,
            stroke,
          );
        }
      case GhostEyes.sleepy:
        for (final x in [ex1, ex2]) {
          // Demi-lune : paupière à moitié fermée.
          canvas.drawArc(
            Rect.fromCenter(
                center: Offset(x, ey), width: w * 0.13, height: w * 0.13),
            0,
            math.pi,
            true,
            fill,
          );
        }
      case GhostEyes.hearts:
        final pink = Paint()..color = const Color(0xFFFF4D8D);
        canvas.drawPath(_heart(Offset(ex1, ey), w * 0.07), pink);
        canvas.drawPath(_heart(Offset(ex2, ey), w * 0.07), pink);
      case GhostEyes.narrow:
        ovalEye(ex1, w * 0.06, w * 0.028);
        ovalEye(ex2, w * 0.06, w * 0.028);
      case GhostEyes.sunglasses:
        for (final x in [ex1, ex2]) {
          canvas.drawRRect(
            RRect.fromLTRBR(x - w * 0.12, ey - w * 0.07, x + w * 0.12,
                ey + w * 0.09, Radius.circular(w * 0.045)),
            fill,
          );
        }
        canvas.drawLine(
          Offset(ex1 + w * 0.1, ey - w * 0.04),
          Offset(ex2 - w * 0.1, ey - w * 0.04),
          stroke..strokeWidth = w * 0.025,
        );
        stroke.strokeWidth = w * 0.032;
        final glint = Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..strokeWidth = w * 0.02
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(ex1 - w * 0.07, ey - w * 0.03),
            Offset(ex1 - w * 0.03, ey - w * 0.03), glint);
        canvas.drawLine(Offset(ex2 - w * 0.07, ey - w * 0.03),
            Offset(ex2 - w * 0.03, ey - w * 0.03), glint);
      case GhostEyes.wink:
        ovalEye(ex1, w * 0.06, w * 0.075);
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(ex2, ey - w * 0.01), width: w * 0.15, height: w * 0.15),
          0.2,
          math.pi - 0.4,
          false,
          stroke,
        );
    }

    // Sourcils.
    if (brows != GhostBrows.none) {
      final by = ey - w * 0.13;
      final slope = brows == GhostBrows.determined ? w * 0.018 : w * 0.035;
      // « inner » : le côté du sourcil le plus proche du centre du visage.
      final innerLow = brows != GhostBrows.sad;
      for (final left in [true, false]) {
        final x = left ? ex1 : ex2;
        final dir = left ? 1.0 : -1.0; // vers le centre
        final inner = Offset(x + dir * w * 0.07, by + (innerLow ? slope : -slope));
        final outer = Offset(x - dir * w * 0.07, by + (innerLow ? -slope : slope));
        canvas.drawLine(inner, outer, stroke);
      }
    }

    // Bouche.
    switch (mouth) {
      case GhostMouth.smile:
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.11, my)
            ..quadraticBezierTo(cx, my + w * 0.1, cx + w * 0.11, my),
          stroke,
        );
      case GhostMouth.grin:
        final rect = Rect.fromCenter(
            center: Offset(cx, my), width: w * 0.26, height: w * 0.22);
        canvas.drawPath(Path()..arcTo(rect, 0, math.pi, false)..close(), fill);
      case GhostMouth.frown:
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.09, my + w * 0.03)
            ..quadraticBezierTo(cx, my - w * 0.06, cx + w * 0.09, my + w * 0.03),
          stroke,
        );
      case GhostMouth.flat:
        canvas.drawLine(
            Offset(cx - w * 0.07, my), Offset(cx + w * 0.07, my), stroke);
      case GhostMouth.smirk:
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.09, my)
            ..quadraticBezierTo(
                cx + w * 0.02, my + w * 0.06, cx + w * 0.1, my - w * 0.04),
          stroke,
        );
      case GhostMouth.tinyO:
        canvas.drawCircle(Offset(cx, my + w * 0.01), w * 0.035, stroke);
      case GhostMouth.tongue:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx + w * 0.01, my + w * 0.02, w * 0.075, w * 0.1),
            Radius.circular(w * 0.035),
          ),
          Paint()..color = const Color(0xFFFF7A9C),
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.11, my)
            ..quadraticBezierTo(cx, my + w * 0.1, cx + w * 0.11, my),
          stroke,
        );
    }
  }

  // ---------------------------------------------------------------------
  // Accessoires
  // ---------------------------------------------------------------------

  void _paintExtra(Canvas canvas, double w, double top, double frac) {
    final extra = playing ? look.extra : GhostExtra.zzz;
    final ex1 = w * 0.34;
    final ex2 = w * 0.66;
    final ey = top + w * 0.46;

    switch (extra) {
      case GhostExtra.none:
        break;
      case GhostExtra.tear:
        final dy = frac * w * 0.1;
        final p = Path()
          ..moveTo(ex1, ey + w * 0.1 + dy)
          ..quadraticBezierTo(
              ex1 + w * 0.05, ey + w * 0.16 + dy, ex1, ey + w * 0.2 + dy)
          ..quadraticBezierTo(
              ex1 - w * 0.05, ey + w * 0.16 + dy, ex1, ey + w * 0.1 + dy);
        canvas.drawPath(
          p,
          Paint()
            ..color = const Color(0xFF5BC0FF).withValues(alpha: 1 - frac * 0.6),
        );
      case GhostExtra.blush:
        final blush = Paint()..color = const Color(0xFFFF6FA0).withValues(alpha: 0.45);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(ex1 - w * 0.03, ey + w * 0.13),
                width: w * 0.13,
                height: w * 0.07),
            blush);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(ex2 + w * 0.03, ey + w * 0.13),
                width: w * 0.13,
                height: w * 0.07),
            blush);
      case GhostExtra.halo:
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(w / 2, top - w * 0.03),
              width: w * 0.5,
              height: w * 0.11),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.035
            ..color = const Color(0xFFFFD35A),
        );
      case GhostExtra.zzz:
        _text(canvas, 'z', Offset(w * 0.78, top - w * 0.02), w * 0.17,
            Colors.white.withValues(alpha: 0.9));
        _text(canvas, 'Z', Offset(w * 0.92, top - w * 0.15), w * 0.23,
            Colors.white.withValues(alpha: 0.7));
      case GhostExtra.confetti:
        const colors = [
          Color(0xFFFF5D8F),
          Color(0xFFFFD35A),
          Color(0xFF5BC0FF),
          Color(0xFF7CFFB2),
          Color(0xFFB28DFF),
          Color(0xFFFF9F43),
        ];
        for (var i = 0; i < colors.length; i++) {
          final f = (frac + i / colors.length) % 1.0;
          canvas.drawCircle(
            Offset(w * (0.08 + 0.17 * i), top + w * 0.1 - f * w * 0.2),
            w * 0.028,
            Paint()..color = colors[i].withValues(alpha: 1 - f),
          );
        }
      case GhostExtra.notes:
        for (var i = 0; i < 2; i++) {
          final f = (frac + i * 0.5) % 1.0;
          _text(
            canvas,
            i == 0 ? '♪' : '♫',
            Offset(w * (i == 0 ? 0.82 : 0.14) + math.sin(f * 2 * math.pi) * w * 0.03,
                top + w * 0.05 - f * w * 0.2),
            w * 0.2,
            Colors.white.withValues(alpha: 1 - f),
          );
        }
      case GhostExtra.glasses:
        final frame = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.022
          ..color = _ink;
        canvas.drawCircle(Offset(ex1, ey), w * 0.11, frame);
        canvas.drawCircle(Offset(ex2, ey), w * 0.11, frame);
        canvas.drawLine(Offset(ex1 + w * 0.11, ey), Offset(ex2 - w * 0.11, ey), frame);
    }
  }

  Path _heart(Offset c, double s) {
    return Path()
      ..moveTo(c.dx, c.dy + s * 0.9)
      ..cubicTo(c.dx - s * 1.6, c.dy - s * 0.1, c.dx - s * 0.8, c.dy - s * 1.2,
          c.dx, c.dy - s * 0.4)
      ..cubicTo(c.dx + s * 0.8, c.dy - s * 1.2, c.dx + s * 1.6, c.dy - s * 0.1,
          c.dx, c.dy + s * 0.9)
      ..close();
  }

  void _text(Canvas canvas, String s, Offset center, double fontSize, Color c) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: c,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.t != t ||
      old.look != look ||
      old.color != color ||
      old.playing != playing;
}
