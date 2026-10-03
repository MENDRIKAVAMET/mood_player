import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../theme/app_theme.dart';

/// Bouton d'en-tête : icône seule, sans fond ni bordure. La zone tactile
/// fait 44x44 (taille recommandée), avec un léger retour haptique.
class AppHeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;

  const AppHeaderButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap!();
            }
          : null,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          size: 24,
          color: (color ?? AppTheme.textPrimary)
              .withValues(alpha: enabled ? 1 : 0.4),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Raccourcis globaux (recherche + profil), présents dans l'en-tête de
/// chaque onglet pour qu'on les retrouve toujours au même endroit.
class HeaderActions extends StatelessWidget {
  final bool showSearch;
  final bool showProfile;

  const HeaderActions({
    super.key,
    this.showSearch = true,
    this.showProfile = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSearch)
          AppHeaderButton(
            icon: Icons.search_rounded,
            tooltip: 'Rechercher',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        if (showProfile)
          AppHeaderButton(
            icon: Icons.person_outline_rounded,
            tooltip: 'Profil',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
      ],
    );
  }
}
