import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Bouton icône circulaire réutilisable : le cercle visuel peut être petit
/// (ex. 32px, pour rester discret dans un en-tête de section) mais la zone
/// tactile réelle fait toujours au moins [minTapTarget] - 44px par défaut,
/// la taille minimale recommandée (iOS/Material) - centrée dessus. Un léger
/// retour haptique accompagne chaque appui.
///
/// Avant ce widget, plusieurs boutons de l'app (shuffle, "voir tout"...)
/// étaient des `GestureDetector` de 32x32 sans marge : la zone tactile
/// réelle était plus petite que recommandé.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double circleSize;
  final double minTapTarget;
  final double iconSize;
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final String? tooltip;
  final bool haptic;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.circleSize = 32,
    this.minTapTarget = 44,
    this.iconSize = 16,
    this.iconColor,
    this.backgroundColor,
    this.borderColor,
    this.tooltip,
    this.haptic = true,
  });

  @override
  Widget build(BuildContext context) {
    final tapTarget = circleSize > minTapTarget ? circleSize : minTapTarget;

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (haptic) HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: tapTarget,
        height: tapTarget,
        child: Center(
          child: Container(
            width: circleSize,
            height: circleSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor ?? AppTheme.border,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppTheme.textSecondary,
              size: iconSize,
            ),
          ),
        ),
      ),
    );

    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}
