import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Fond d'écran plein cadre à partir de l'image d'une ambiance : floutée
/// (les images sont en paysage et peu larges, nettes elles seraient très
/// agrandies sur un écran en portrait) sous un voile sombre teinté de
/// [tint], pour que la liste par-dessus reste lisible.
///
/// À placer en premier dans un `Stack` qui remplit l'écran.
class MoodBackdrop extends StatelessWidget {
  final Widget image;
  final Color tint;

  const MoodBackdrop({super.key, required this.image, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: image,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tint.withValues(alpha: 0.25),
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.35, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
