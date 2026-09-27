import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingS,
                  AppTheme.spacingS,
                  AppTheme.spacingL,
                  AppTheme.spacingS,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppTheme.textPrimary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: AppTheme.headlineLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tracks.isNotEmpty)
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
                          child: const Icon(Icons.play_arrow_rounded,
                              color: AppTheme.textPrimary, size: 18),
                        ),
                      ),
                  ],
                ),
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
