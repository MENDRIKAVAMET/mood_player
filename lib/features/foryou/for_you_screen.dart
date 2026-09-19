import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/compact_track_card.dart';
import '../../widgets/foryou_list_row.dart';
import '../search/search_screen.dart';

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
    final suggested = ref.watch(suggestedTracksProvider);
    final timeBasedSuggestions = ref.watch(timeBasedSuggestionsProvider);
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
                // Les suggestions du moment passent en tout premier :
                // elles changent avec l'heure de la journée (matin/midi/
                // soir), donc c'est le contenu le plus "vivant" de la
                // page - contrairement aux autres sections qui ne
                // bougent qu'avec de nouvelles écoutes.
                _carouselSection(
                  context: context,
                  title: titleForPeriod(dayPeriod),
                  tracks: timeBasedSuggestions,
                  emptyMessage:
                      'Classe quelques morceaux par ambiance pour voir des '
                      'suggestions apparaître ici selon le moment de la '
                      'journée.',
                ),
                // Les suggestions passent en tête : c'est la seule section
                // que l'utilisateur ne peut pas retrouver ailleurs dans
                // l'app, donc c'est elle qui justifie la page.
                _carouselSection(
                  context: context,
                  title: 'Suggestions pour toi',
                  tracks: suggested,
                  emptyMessage:
                      'Les suggestions arrivent dès que tu as écouté ou aimé '
                      'quelques morceaux.',
                ),
                _carouselSection(
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
          IconButton(
            tooltip: 'Rechercher',
            icon: const Icon(Icons.search_rounded, color: AppTheme.textPrimary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
    );
  }

  /// En-tête de section commun aux deux gabarits : titre à gauche, pastille
  /// « Jouer » pleine et bouton shuffle à droite — repris directement du
  /// placement des en-têtes « Recommandé » / « Récemment Écouté » des
  /// captures de référence, plutôt que les icônes nues utilisées avant.
  Widget _sectionHeader(BuildContext context, String title, List<Track> tracks) {
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
            GestureDetector(
              onTap: () => playShuffled(context, tracks),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: const Icon(
                  Icons.shuffle_rounded,
                  color: AppTheme.textSecondary,
                  size: 16,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Gabarit carrousel (« Recommandé » / « Dernier Ajout ») : cartes
  /// carrées avec médaillon lecture, titre et artiste en dessous.
  Widget _carouselSection({
    required BuildContext context,
    required String title,
    required List<Track> tracks,
    String? emptyMessage,
  }) {
    if (tracks.isEmpty && emptyMessage == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, title, tracks),
          if (tracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
              child: Text(
                emptyMessage!,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              ),
            )
          else
            SizedBox(
              height: 196,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return CompactTrackCard(
                    track: track,
                    onTap: () => openPlayer(context, track: track, tracks: tracks),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Gabarit liste (« Récemment Écouté » / « Les Plus Joués ») : lignes
  /// empilées verticalement, jusqu'à 6 pour ne pas transformer la page en
  /// simple doublon de la bibliothèque.
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

    final shown = tracks.take(6).toList();

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, title, tracks),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
              child: Text(
                emptyMessage!,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              ),
            )
          else
            Column(
              children: [
                for (final track in shown)
                  ForYouListRow(
                    track: track,
                    badge: badgeBuilder?.call(track),
                    onTap: () => openPlayer(context, track: track, tracks: tracks),
                  ),
              ],
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
