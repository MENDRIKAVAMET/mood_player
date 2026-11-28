import 'package:flutter/material.dart';

import '../models/mood_journal_entry.dart';
import '../theme/app_theme.dart';

/// Icône « ligne » d'une humeur (visage, cœur, zZ…), dessinée dans la couleur
/// d'accent de l'app. Remplace les emojis couleur du système, qui ne suivent
/// pas le thème et changent d'un téléphone à l'autre.
class FeelingIcon extends StatelessWidget {
  final Feeling feeling;
  final double size;
  final Color? color;

  const FeelingIcon({
    super.key,
    required this.feeling,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.accentPrimary;
    switch (feeling) {
      case Feeling.inLove:
        return Icon(Icons.favorite_border_rounded, size: size, color: c);
      case Feeling.motivated:
        return Icon(Icons.sports_mma_outlined, size: size, color: c);
      case Feeling.tired:
        return _Zzz(size: size, color: c);
      case Feeling.joyful:
      case Feeling.calm:
      case Feeling.stressed:
      case Feeling.sad:
      case Feeling.angry:
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _FacePainter(feeling, c)),
        );
    }
  }
}

class _Zzz extends StatelessWidget {
  final double size;
  final Color color;

  const _Zzz({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    TextStyle style(double factor) => TextStyle(
          fontSize: size * factor,
          height: 1,
          color: color,
          fontWeight: FontWeight.w500,
        );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: size * 0.04,
            bottom: size * 0.04,
            child: Text('z',
                textScaler: TextScaler.noScaling, style: style(0.55)),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Text('Z',
                textScaler: TextScaler.noScaling, style: style(0.62)),
          ),
        ],
      ),
    );
  }
}

/// Visages en trait fin, dessinés sur une grille de 24 x 24.
class _FacePainter extends CustomPainter {
  final Feeling feeling;
  final Color color;

  const _FacePainter(this.feeling, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(12, 12), 10.5, line);

    void dots() {
      canvas.drawCircle(const Offset(9, 10), 1, dot);
      canvas.drawCircle(const Offset(15, 10), 1, dot);
    }

    final p = Path();
    switch (feeling) {
      case Feeling.joyful:
        p
          ..moveTo(7.4, 10.4)
          ..quadraticBezierTo(9, 8.2, 10.6, 10.4)
          ..moveTo(13.4, 10.4)
          ..quadraticBezierTo(15, 8.2, 16.6, 10.4)
          ..moveTo(7.4, 14)
          ..quadraticBezierTo(12, 19.4, 16.6, 14);
      case Feeling.calm:
        p
          ..moveTo(7.4, 10.2)
          ..quadraticBezierTo(9, 12, 10.6, 10.2)
          ..moveTo(13.4, 10.2)
          ..quadraticBezierTo(15, 12, 16.6, 10.2)
          ..moveTo(9.6, 15.2)
          ..quadraticBezierTo(12, 17, 14.4, 15.2);
      case Feeling.stressed:
        dots();
        p
          ..moveTo(7.2, 7.8)
          ..lineTo(10.4, 6.8)
          ..moveTo(16.8, 7.8)
          ..lineTo(13.6, 6.8)
          ..moveTo(7.8, 16)
          ..cubicTo(9.2, 14.2, 10.6, 17.8, 12, 16)
          ..cubicTo(13.4, 14.2, 14.8, 17.8, 16.2, 16);
      case Feeling.sad:
        dots();
        p
          ..moveTo(8.6, 16.6)
          ..quadraticBezierTo(12, 13, 15.4, 16.6);
      case Feeling.angry:
        dots();
        p
          ..moveTo(7, 7.4)
          ..lineTo(10.6, 9)
          ..moveTo(17, 7.4)
          ..lineTo(13.4, 9)
          ..moveTo(8.8, 16.2)
          ..quadraticBezierTo(12, 13.6, 15.2, 16.2);
      case Feeling.inLove:
      case Feeling.motivated:
      case Feeling.tired:
        break;
    }
    canvas.drawPath(p, line);
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.feeling != feeling || old.color != color;
}

/// Bouton d'humeur : pastille à contour clair, icône + libellé.
class FeelingChip extends StatelessWidget {
  final Feeling feeling;
  final VoidCallback onTap;

  const FeelingChip({super.key, required this.feeling, required this.onTap});

  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(_radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.78),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FeelingIcon(feeling: feeling, size: 20),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                feeling.label,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toutes les humeurs en pastilles, avec les mêmes espacements partout
/// (journal d'humeur et carte « Comment tu te sens ? » de Découvertes).
class FeelingChipWrap extends StatelessWidget {
  final ValueChanged<Feeling> onSelected;

  const FeelingChipWrap({super.key, required this.onSelected});

  static const double spacing = AppTheme.spacingS;
  static const double runSpacing = 20;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: [
        for (final f in Feeling.values)
          FeelingChip(feeling: f, onTap: () => onSelected(f)),
      ],
    );
  }
}

/// Barre de pourcentage : piste sombre translucide, remplissage en dégradé
/// doré (couleurs d'accent de l'app), bouts arrondis.
class FeelingBar extends StatelessWidget {
  final double value;

  const FeelingBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    const h = 6.0;
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(h / 2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0).toDouble(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
              ),
              borderRadius: BorderRadius.circular(h / 2),
            ),
          ),
        ),
      ),
    );
  }
}
