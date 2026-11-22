import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Floute ce qui se trouve derrière [child] quand le thème Verre est actif
/// (sinon, ne change rien). À poser autour d'une surface translucide qui
/// recouvre du contenu : barre du bas, mini-lecteur...
class GlassBlur extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final double sigma;

  const GlassBlur({
    super.key,
    required this.child,
    this.borderRadius,
    this.sigma = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppTheme.glass) return child;
    final blurred = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
    return borderRadius == null
        ? ClipRect(child: blurred)
        : ClipRRect(borderRadius: borderRadius!, child: blurred);
  }
}
