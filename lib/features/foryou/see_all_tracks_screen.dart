import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../theme/app_theme.dart';
import '../../providers/track_provider.dart' show TrackSortOption;
import '../../utils/playback_navigation.dart';
import '../../widgets/app_header.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/track_list_tools.dart';
import '../../widgets/track_tile.dart';

/// Liste complète pour une section de « Pour vous » (Récemment écouté,
/// Les plus écoutés, Tes morceaux aimés...) dont l'aperçu sur la page
/// d'accueil est plafonné à 9 morceaux. Ouvert depuis le bouton « voir
/// tout » (chevron) de chaque section.
class SeeAllTracksScreen extends StatefulWidget {
  final String title;
  final List<Track> tracks;

  const SeeAllTracksScreen({
    super.key,
    required this.title,
    required this.tracks,
  });

  @override
  State<SeeAllTracksScreen> createState() => _SeeAllTracksScreenState();
}

class _SeeAllTracksScreenState extends State<SeeAllTracksScreen> {
  final ScrollController _scroll = ScrollController();
  late final TrackListLocator _locator =
      TrackListLocator(controller: _scroll);
  TrackSortOption? _sort;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final tracks =
        _sort == null ? widget.tracks : sortTracks(widget.tracks, _sort!);
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
                  TrackListActionBar(
                    tracks: tracks,
                    sort: _sort,
                    onSort: (c) => setState(() => _sort = c.option),
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
                    : Stack(
                        children: [
                          TrackListScrollbar(
                            controller: _scroll,
                            child: ListView.builder(
                              controller: _scroll,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 120),
                              itemCount: tracks.length,
                              itemBuilder: (context, index) {
                                final track = tracks[index];
                                return KeyedSubtree(
                                  key: _locator.keyFor(track.id),
                                  child: TrackTile(
                                    track: track,
                                    index: index,
                                    onTap: () => openPlayer(
                                      context,
                                      track: track,
                                      tracks: tracks,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          LocateTrackButton(locator: _locator, tracks: tracks),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
