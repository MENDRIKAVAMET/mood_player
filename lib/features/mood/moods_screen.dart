import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/classify_progress_banner.dart';
import '../../widgets/custom_mood_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/mood_card.dart';
import '../../widgets/mood_editor_dialog.dart';
import 'custom_mood_detail_screen.dart';
import 'mood_detail_screen.dart';

/// Onglet dédié aux ambiances : les moods créés par l'utilisateur et les
/// ambiances détectées automatiquement.
///
/// Ces deux carrousels vivaient auparavant en haut de l'accueil, où ils
/// mangeaient environ 400 px de hauteur avant même que la liste des
/// morceaux ne commence. Ici, ils ont toute la place — et la
/// bibliothèque respire.
class MoodsScreen extends ConsumerWidget {
  const MoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customMoods = ref.watch(customMoodProvider).moods;
    final libraryHasTracks = ref.watch(trackProvider).tracks.isNotEmpty;
    final trackCountByMood = ref.watch(trackCountByMoodProvider);
    final trackState = ref.watch(trackProvider);
    final moodsWithTracks = trackCountByMood.entries
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppHeader.tab(title: 'Ambiances'),
              Expanded(
                child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              // Progression directement sur cet onglet (plus de simple
              // SnackBar) : la même bannière que dans la Bibliothèque.
              if (trackState.isClassifying)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacingM),
                  child: ClassifyProgressBanner(
                    progress: trackState.classifyProgress!,
                    total: trackState.classifyTotal!,
                    statusMessage: trackState.classifyStatusMessage,
                  ),
                ),

              _sectionHeader('Mes moods', customMoods.isEmpty ? null : customMoods.length),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                child: _MoodGrid(
                  itemCount: customMoods.length + 1,
                  itemBuilder: (context, index) {
                    if (index == customMoods.length) {
                      return CreateMoodCard(
                        onTap: () => _createCustomMood(context, ref),
                      );
                    }
                    final mood = customMoods[index];
                    return CustomMoodCard(
                      mood: mood,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomMoodDetailScreen(mood: mood),
                        ),
                      ),
                    );
                  },
                ),
              ),

              _sectionHeader('Par ambiance', null),
              if (moodsWithTracks.isEmpty)
                _emptyAmbianceState(
                  context,
                  ref,
                  libraryHasTracks: libraryHasTracks,
                  isClassifying: trackState.isClassifying,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                  child: _MoodGrid(
                    itemCount: moodsWithTracks.length,
                    itemBuilder: (context, index) {
                      final mood = moodsWithTracks[index];
                      return MoodCard(
                        mood: mood,
                        trackCount: trackCountByMood[mood] ?? 0,
                        onTap: () => _openMoodDetail(context, ref, mood),
                      );
                    },
                  ),
                ),
            ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingS,
      ),
      child: Row(
        children: [
          Text(title, style: AppTheme.headlineMedium),
          if (count != null) ...[
            const SizedBox(width: AppTheme.spacingS),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingS,
                vertical: AppTheme.spacingXXS,
              ),
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusS),
              ),
              child: Text(
                '$count',
                style: AppTheme.labelSmall.copyWith(color: AppTheme.accentPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createCustomMood(BuildContext context, WidgetRef ref) async {
    final result = await showMoodEditorDialog(context);
    if (result == null) return;
    await ref.read(customMoodProvider.notifier).createMood(
          name: result.$1,
          icon: result.$2,
          colorValue: result.$3,
        );
  }

  /// Remplace l'ancien simple texte gris par un vrai état vide (icône,
  /// titre, description et un bouton qui agit - pas juste "va voir
  /// ailleurs"), cohérent avec celui de « Pour vous ». Le message change
  /// selon qu'il n'y a tout simplement aucun morceau, ou qu'il y en a mais
  /// qu'aucun n'est encore classifié.
  Widget _emptyAmbianceState(
    BuildContext context,
    WidgetRef ref, {
    required bool libraryHasTracks,
    required bool isClassifying,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingL,
        AppTheme.spacingXL,
        AppTheme.spacingL,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                libraryHasTracks
                    ? Icons.auto_awesome_rounded
                    : Icons.library_music_rounded,
                size: 30,
                color: AppTheme.accentPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              libraryHasTracks
                  ? 'Tes morceaux n\'ont pas encore d\'ambiance'
                  : 'Aucun morceau pour l\'instant',
              style: AppTheme.headlineMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              libraryHasTracks
                  ? 'Lance la classification : chaque morceau sera rangé '
                      'automatiquement dans une ambiance (énergique, chill, '
                      'triste...).'
                  : 'Ajoute ou scanne de la musique depuis l\'onglet '
                      'Bibliothèque pour commencer.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
              textAlign: TextAlign.center,
            ),
            if (libraryHasTracks && !isClassifying) ...[
              const SizedBox(height: AppTheme.spacingL),
              GestureDetector(
                onTap: () => _confirmClassify(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingXL,
                    vertical: AppTheme.spacingM,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: AppTheme.spacingS),
                      Text(
                        'Classifier maintenant',
                        style: AppTheme.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              TextButton(
                onPressed: () => _startClassify(ref, limit: 20),
                child: Text(
                  'ou classifier seulement les 20 premiers',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textTertiary,
                    decoration: TextDecoration.underline,
                    decorationColor: AppTheme.textTertiary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startClassify(WidgetRef ref, {int? limit}) {
    // La bannière de progression s'affiche en haut de cet écran dès que
    // l'état passe en « classification en cours ».
    ref.read(trackProvider.notifier).classifyAllUnclassified(limit: limit);
  }

  void _confirmClassify(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Classifier tous les morceaux', style: AppTheme.headlineMedium),
        content: Text(
          'Voulez-vous classifier tous les morceaux non classifiés ? '
          'Cela peut prendre du temps selon le nombre de morceaux.',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _startClassify(ref);
            },
            child: Text('Classifier', style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
    );
  }

  void _openMoodDetail(BuildContext context, WidgetRef ref, MoodType mood) {
    final tracks = ref.read(tracksByMoodProvider(mood));
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MoodDetailScreen(mood: mood, tracks: tracks),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: AppTheme.animPageTransition,
      ),
    );
  }
}

/// Grille responsive pour les cartes de mood : 2 colonnes sur un petit
/// écran, jusqu'à 4 sur un écran large, plutôt qu'un carrousel horizontal
/// - avec 17 ambiances possibles désormais (9 de base + 8 ajoutées), tout
/// faire tenir dans une seule ligne défilante n'était plus praticable.
class _MoodGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  const _MoodGrid({required this.itemCount, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Chaque carte fait au plus 190px de large - ça donne 2 colonnes
        // sur un téléphone étroit, 3-4 sur un téléphone large ou une
        // tablette, calculé automatiquement selon l'espace disponible.
        maxCrossAxisExtent: 190,
        mainAxisSpacing: AppTheme.spacingM,
        crossAxisSpacing: AppTheme.spacingM,
        childAspectRatio: 0.82,
      ),
      itemBuilder: itemBuilder,
    );
  }
}
