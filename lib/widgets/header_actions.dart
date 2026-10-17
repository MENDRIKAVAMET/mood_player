import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../providers/providers.dart';
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

/// Raccourcis globaux (recherche ; le profil a désormais son propre onglet
/// dans la barre du bas), présents dans l'en-tête de chaque onglet pour qu'on les retrouve toujours au même endroit.
class HeaderActions extends StatelessWidget {
  final bool showClassify;
  final bool showSearch;
  final bool showProfile;

  const HeaderActions({
    super.key,
    this.showClassify = true,
    this.showSearch = true,
    this.showProfile = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showClassify) const ClassifyHeaderButton(),
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


/// Bouton « Classer » de l'en-tête, identique dans tous les onglets :
/// icône seule (palette de couleurs) dans un cercle aux couleurs de la
/// marque. Le cercle visible fait 38 px, la zone tactile 44 px. Désactivé
/// (grisé) pendant une classification en cours.
class ClassifyHeaderButton extends ConsumerWidget {
  const ClassifyHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isClassifying = ref.watch(trackProvider).isClassifying;
    return Tooltip(
      message: 'Classifier les morceaux',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isClassifying ? null : () => _confirm(context, ref),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Opacity(
              opacity: isClassifying ? 0.5 : 1,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentPrimary.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.color_lens_rounded,
                  size: 21,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirm(BuildContext context, WidgetRef ref) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Classifier tous les morceaux',
            style: AppTheme.headlineMedium),
        content: Text(
          'Voulez-vous classifier tous les morceaux non classifiés ? '
          'Cela peut prendre du temps selon le nombre de morceaux.',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Annuler',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(trackProvider.notifier).classifyAllUnclassified();
            },
            child: Text('Classifier',
                style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
    );
  }
}
