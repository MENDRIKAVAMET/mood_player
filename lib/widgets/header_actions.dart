import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../theme/app_theme.dart';

/// Bouton carré arrondi des en-têtes d'onglet (44x44 : zone tactile
/// recommandée), avec léger retour haptique. Remplace les
/// `GestureDetector` + `Container` recopiés à la main dans chaque écran.
class AppHeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const AppHeaderButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: Icon(icon, color: AppTheme.textPrimary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Raccourcis globaux (recherche + profil) présents en haut de chaque
/// onglet, pour qu'on les retrouve toujours au même endroit. Sur la
/// bibliothèque, la recherche a déjà sa barre dédiée : [showSearch] = false.
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
        if (showSearch && showProfile) const SizedBox(width: AppTheme.spacingS),
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
