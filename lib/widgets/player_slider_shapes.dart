import 'package:flutter/material.dart';

/// Piste de lecture : partie déjà lue en dégradé, reste en gris translucide,
/// extrémités arrondies.
class GradientTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final Gradient gradient;

  const GradientTrackShape({required this.gradient});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(trackRect.height / 2);
    final canvas = context.canvas;

    // Piste complète (partie non lue).
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.white24,
    );

    // Partie lue, remplie avec le dégradé.
    final activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx.clamp(trackRect.left, trackRect.right),
      trackRect.bottom,
    );
    if (activeRect.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()..shader = gradient.createShader(trackRect),
      );
    }
  }
}

/// Curseur : pastille blanche avec un halo lumineux de la couleur de marque.
class GlowThumbShape extends SliderComponentShape {
  final Color glow;
  static const double radius = 8;

  const GlowThumbShape({required this.glow});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..color = glow.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
  }
}
