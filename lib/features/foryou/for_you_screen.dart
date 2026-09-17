import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/compact_track_card.dart';
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
                // Les suggestions passent en tête : c'est la seule section
                // que l'utilisateur ne peut pas retrouver ailleurs dans
                // l'app, donc c'est elle qui justifie la page.
                _section(
                  context: context,
                  title: 'Suggestions pour toi',
                  subtitle: 'À partir de ce que tu écoutes et de ce que tu aimes',
                  tracks: suggested,
                  emptyMessage:
                      'Les suggestions arrivent dès que tu as écouté ou aimé '
                      'quelques morceaux.',
                ),
                _section(
                  context: context,
                  title: 'Ajoutés récemment',
                  subtitle: 'Les derniers morceaux arrivés dans ta bibliothèque',
                  tracks: recentlyAdded,
                ),
                _section(
                  context: context,
                  title: 'Les plus écoutés',
                  subtitle: 'Écoutés à plus de 80 % de leur durée',
                  tracks: mostPlayed,
                  badgeBuilder: (track) {
                    final count = playCounts[track.id] ?? 0;
                    return count > 1 ? '$count écoutes' : '1 écoute';
                  },
                  emptyMessage:
                      'Rien encore. Un morceau apparaît ici une fois écouté '
                      'à plus de 80 % — le passer en vitesse ne compte pas.',
                ),
                _section(
                  context: context,
                  title: 'Tes morceaux aimés',
                  subtitle: 'Tout ce que tu as mis en favori',
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

  /// Une section horizontale. Si [tracks] est vide et qu'un
  /// [emptyMessage] est fourni, la section reste visible avec une
  /// explication — c'est plus utile qu'une section qui disparaît sans
  /// que l'utilisateur comprenne pourquoi.
  Widget _section({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<Track> tracks,
    String Function(Track track)? badgeBuilder,
    String? emptyMessage,
  }) {
    if (tracks.isEmpty && emptyMessage == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppTheme.spacingL,
          AppTheme.spacingL,
          AppTheme.spacingL,
          0,
        ),
        padding: const EdgeInsets.only(bottom: AppTheme.spacingL),
        decoration: AppTheme.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingL,
                AppTheme.spacingL,
                AppTheme.spacingS,
                AppTheme.spacingXS,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTheme.headlineMedium),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tracks.isNotEmpty) ...[
                    IconButton(
                      tooltip: 'Tout lire',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.play_arrow_rounded,
                          color: AppTheme.accentPrimary, size: 24),
                      onPressed: () => playAll(context, tracks),
                    ),
                    IconButton(
                      tooltip: 'Lecture aléatoire',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.shuffle_rounded,
                          color: AppTheme.accentPrimary, size: 22),
                      onPressed: () => playShuffled(context, tracks),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
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
                      badge: badgeBuilder?.call(track),
                      onTap: () => openPlayer(context, track: track, tracks: tracks),
                    );
                  },
                ),
              ),
          ],
        ),
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
