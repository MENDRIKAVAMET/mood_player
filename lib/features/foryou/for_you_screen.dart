import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/foryou_list_row.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/period_mixes_section.dart';
import '../../widgets/suggestion_mix_card.dart';
import 'see_all_tracks_screen.dart';
import 'suggestion_mix_screen.dart';

/// Page « Pour vous » : ajouts récents, morceaux réellement les plus
/// écoutés, favoris, et suggestions déduites des deux derniers.
///
/// « Le plus écouté » ne veut pas dire « le plus lancé » : un morceau
/// n'est compté que s'il a été écouté au-delà de 80 % de sa durée (voir
/// [playbackStatsProvider]).
class ForYouScreen extends ConsumerWidget {
  const ForYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyAdded = ref.watch(recentlyAddedTracksProvider);
    final mostPlayed = ref.watch(mostPlayedTracksProvider);
    final liked = ref.watch(likedTracksProvider);
    final suggestedMixes = ref.watch(suggestedMixesProvider);
    final dayPeriod = ref.watch(dayPeriodProvider);
    final playCounts = ref.watch(playbackStatsProvider);
    final isEmpty = ref.watch(trackProvider).tracks.isEmpty;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              if (isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else ...[
                // Les mixes du moment passent en tout premier : 5 cartes
                // de 20 morceaux, uniquement pour le moment de la journée
                // en cours (matin, midi ou soir).
                SliverToBoxAdapter(
                  child: PeriodMixesSection(period: dayPeriod),
                ),
                // Les suggestions passent juste après : c'est la seule
                // section que l'utilisateur ne peut pas retrouver ailleurs
                // dans l'app, donc c'est elle qui justifie la page. Même
                // gabarit que les mixes du moment juste au-dessus : 5 mixes
                // de 20 morceaux, tirés des artistes préférés, des morceaux
                // écoutés et des morceaux aimés plutôt que de l'heure qu'il
                // est.
                _suggestionMixesSection(context, suggestedMixes),
                _listSection(
                  context: context,
                  title: 'Ajoutés récemment',
                  tracks: recentlyAdded,
                ),
                _listSection(
                  context: context,
                  title: 'Les plus écoutés',
                  tracks: mostPlayed,
                  badgeBuilder: (track) => '${playCounts[track.id] ?? 0}',
                  emptyMessage:
                      'Rien encore. Un morceau apparaît ici une fois écouté '
                      'à plus de 80 % — le passer en vitesse ne compte pas.',
                ),
                _listSection(
                  context: context,
                  title: 'Tes morceaux aimés',
                  tracks: liked,
                  emptyMessage:
                      'Aucun favori pour le moment. Touche le cœur dans le '
                      'lecteur pour en ajouter.',
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingL,
        AppTheme.spacingXL,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pour vous',
                  style: AppTheme.displayLarge,
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  'Ta musique, remise dans ton ordre à toi',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const HeaderActions(),
        ],
      ),
    );
  }

  /// En-tête de section commun aux deux gabarits : titre à gauche, pastille
  /// « Jouer » pleine et bouton shuffle à droite — repris directement du
  /// placement des en-têtes « Recommandé » / « Récemment Écouté » des
  /// captures de référence, plutôt que les icônes nues utilisées avant.
  Widget _sectionHeader(
    BuildContext context,
    String title,
    List<Track> tracks, {
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingXL,
        AppTheme.spacingL,
        AppTheme.spacingM,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTheme.headlineLarge,
            ),
          ),
          if (tracks.isNotEmpty) ...[
            GestureDetector(
              onTap: () => playAll(context, tracks),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingM,
                  vertical: AppTheme.spacingXS,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded,
                        color: AppTheme.textPrimary, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Jouer',
                      style: AppTheme.labelMedium.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingS),
            AppIconButton(
              icon: Icons.shuffle_rounded,
              onTap: () => playShuffled(context, tracks),
            ),
          ],
          // Bouton "voir tout" - icône seule, sans libellé, affiché
          // uniquement quand l'aperçu (9 morceaux max) ne montre pas
          // déjà la liste complète.
          if (onSeeAll != null) ...[
            const SizedBox(width: AppTheme.spacingS),
            AppIconButton(
              icon: Icons.chevron_right_rounded,
              iconSize: 18,
              onTap: onSeeAll,
            ),
          ],
        ],
      ),
    );
  }

  /// Section « Suggestions pour toi » : même gabarit que les mixes du
  /// moment (carrousel horizontal de cartes de mix), mais basé sur les
  /// artistes préférés et l'historique d'écoute plutôt que sur le moment
  /// de la journée.
  Widget _suggestionMixesSection(BuildContext context, List<TrackMix> mixes) {
    if (mixes.isEmpty) {
      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingL,
                AppTheme.spacingXL,
                AppTheme.spacingL,
                AppTheme.spacingM,
              ),
              child: Text('Suggestions pour toi', style: AppTheme.headlineLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
              child: Text(
                'Les suggestions arrivent dès que tu as écouté ou aimé '
                'quelques morceaux.',
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              ),
            ),
          ],
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingL,
              AppTheme.spacingXL,
              AppTheme.spacingL,
              AppTheme.spacingM,
            ),
            child: Text('Suggestions pour toi', style: AppTheme.headlineLarge),
          ),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
              itemCount: mixes.length,
              itemBuilder: (context, i) => SuggestionMixCard(
                mix: mixes[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SuggestionMixScreen(mix: mixes[i]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gabarit grille (« Ajoutés récemment » / « Les Plus Joués » /
  /// « Tes morceaux aimés ») : des colonnes de 3 lignes empilées, dont on
  /// ne garde que les 3 premières - donc 9 morceaux au maximum - avec un
  /// défilement horizontal entre elles. La largeur d'une colonne ne
  /// change pas : elle reprend celle, pleine largeur, des lignes
  /// d'origine. Le reste de la liste (si elle est plus longue) est
  /// accessible via le bouton « voir tout » de l'en-tête.
  static const int _rowsPerColumn = 3;
  static const int _maxColumns = 3;
  static const double _rowHeight = 68;

  Widget _listSection({
    required BuildContext context,
    required String title,
    required List<Track> tracks,
    String Function(Track track)? badgeBuilder,
    String? emptyMessage,
  }) {
    if (tracks.isEmpty && emptyMessage == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    const maxShown = _rowsPerColumn * _maxColumns;
    final shown = tracks.take(maxShown).toList();
    final columns = <List<Track>>[
      for (var i = 0; i < shown.length; i += _rowsPerColumn)
        shown.sublist(i, (i + _rowsPerColumn).clamp(0, shown.length)),
    ];
    final columnWidth = MediaQuery.sizeOf(context).width - AppTheme.spacingL * 2;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            title,
            tracks,
            onSeeAll: tracks.length > maxShown
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SeeAllTracksScreen(
                          title: title,
                          tracks: tracks,
                        ),
                      ),
                    )
                : null,
          ),
          if (columns.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
              child: Text(
                emptyMessage!,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              ),
            )
          else
            SizedBox(
              height: _rowHeight * _rowsPerColumn,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                itemCount: columns.length,
                itemBuilder: (context, colIndex) {
                  final column = columns[colIndex];
                  return SizedBox(
                    width: columnWidth,
                    child: Column(
                      children: [
                        for (final track in column)
                          ForYouListRow(
                            track: track,
                            badge: badgeBuilder?.call(track),
                            onTap: () =>
                                openPlayer(context, track: track, tracks: tracks),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXXXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 48, color: AppTheme.accentPrimary),
            const SizedBox(height: AppTheme.spacingL),
            Text(
              'Rien à te proposer pour l\'instant',
              style: AppTheme.headlineMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Ajoute ou scanne de la musique depuis l\'onglet Bibliothèque, '
              'et cette page se remplira toute seule.',
              style: AppTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
