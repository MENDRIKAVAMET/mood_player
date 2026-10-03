import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'header_actions.dart';

/// En-tête commun à toutes les pages : même hauteur fixe ([height]), même
/// police, même placement des boutons (sans bordure).
///
/// À poser tout en haut d'une `Column`, DANS un `SafeArea`, et à mettre le
/// contenu défilant dans un `Expanded` en dessous : l'en-tête reste ainsi
/// fixe en haut pendant le défilement.
class AppHeader extends StatelessWidget {
  static const double height = 52;

  final String? title;

  /// Remplace le titre (ex. champ de recherche).
  final Widget? titleWidget;
  final bool showBack;
  final IconData backIcon;
  final VoidCallback? onBack;
  final List<Widget> actions;

  const AppHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.showBack = false,
    this.backIcon = Icons.arrow_back_rounded,
    this.onBack,
    this.actions = const [],
  }) : assert(title != null || titleWidget != null);

  /// En-tête d'onglet : titre + [actions] + recherche + profil.
  const AppHeader.tab({
    super.key,
    required String this.title,
    this.actions = const [HeaderActions()],
  })  : titleWidget = null,
        showBack = false,
        backIcon = Icons.arrow_back_rounded,
        onBack = null;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(
          left: showBack ? AppTheme.spacingXS : AppTheme.spacingL,
          right: AppTheme.spacingXS,
        ),
        child: Row(
          children: [
            if (showBack)
              AppHeaderButton(
                icon: backIcon,
                tooltip: 'Retour',
                onTap: onBack ?? () => Navigator.maybePop(context),
              ),
            Expanded(
              child: titleWidget ??
                  Text(
                    title!,
                    style: AppTheme.headlineLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}
