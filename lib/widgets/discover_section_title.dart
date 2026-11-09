import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Titre de section de l'écran Découvertes : pastille d'icône en dégradé,
/// petit sur-titre optionnel, titre, sous-titre, et un widget à droite
/// (boutons lecture, réglages...).
class DiscoverSectionTitle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  /// Petit texte en capitales au-dessus du titre (ex. « MATIN »).
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  const DiscoverSectionTitle({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light
            ? Colors.black87
            : Colors.white;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, AppTheme.brandBottom, 0.4)!],
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 14,
                spreadRadius: -3,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 22, color: onColor),
        ),
        const SizedBox(width: AppTheme.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null)
                Text(
                  eyebrow!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySmall.copyWith(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.headlineMedium.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
