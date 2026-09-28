import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'header_actions.dart';

/// Barre du haut commune aux trois onglets (Bibliothèque, Pour vous,
/// Ambiances) : le titre de l'onglet à gauche, puis recherche, profil et
/// menu à droite. Posée une seule fois dans la coquille principale, elle
/// reste identique et à la même place quel que soit l'onglet.
class AppTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onMenuTap;

  const AppTopBar({super.key, required this.title, required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingS,
        AppTheme.spacingL,
        AppTheme.spacingS,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.displayMedium,
            ),
          ),
          const HeaderActions(),
          const SizedBox(width: AppTheme.spacingS),
          AppHeaderButton(
            icon: Icons.more_horiz_rounded,
            tooltip: "Plus d'options",
            onTap: onMenuTap,
          ),
        ],
      ),
    );
  }
}
