import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/app_header.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/track_tile.dart';

/// Liste complète pour une section de « Pour vous » (Récemment écouté,
/// Les plus écoutés, Tes morceaux aimés...) dont l'aperçu sur la page
/// d'accueil est plafonné à 9 morceaux. Ouvert depuis le bouton « voir
/// tout » (chevron) de chaque section.
class SeeAllTracksScreen extends StatelessWidget {
  final String title;
  final List<Track> tracks;

  const SeeAllTracksScreen({
    super.key,
    required this.title,
    required this.tracks,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: title,
                showBack: true,
                actions: [
                  if (tracks.isNotEmpty)
                    AppHeaderButton(
                      icon: Icons.play_arrow_rounded,
                      tooltip: 'Tout lire',
                      onTap: () => playAll(context, tracks),
                    ),
                ],
              ),
              Expanded(
                child: tracks.isEmpty
                    ? Center(
                        child: Text(
                          'Rien à afficher pour l\'instant',
                          style: AppTheme.bodyMedium
                              .copyWith(color: AppTheme.textTertiary),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return TrackTile(
                            track: track,
                            index: index,
                            onTap: () => openPlayer(
                              context,
                              track: track,
                              tracks: tracks,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
