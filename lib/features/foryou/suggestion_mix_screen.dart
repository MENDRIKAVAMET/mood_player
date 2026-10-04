import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../providers/mood_suggestions_provider.dart';
import '../../providers/track_provider.dart' show TrackSortOption;
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/app_header.dart';
import '../../widgets/foryou_list_row.dart';
import '../../widgets/track_list_tools.dart';

/// Contenu d'un mix : ses 20 morceaux, avec lecture dans l'ordre ou en
/// aléatoire.
class SuggestionMixScreen extends StatefulWidget {
  final TrackMix mix;

  const SuggestionMixScreen({super.key, required this.mix});

  @override
  State<SuggestionMixScreen> createState() => _SuggestionMixScreenState();
}

class _SuggestionMixScreenState extends State<SuggestionMixScreen> {
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
    final mix = widget.mix;
    final List<Track> tracks =
        _sort == null ? mix.tracks : sortTracks(mix.tracks, _sort!);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                title: '${mix.title} · ${mix.subtitle}',
                showBack: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.spacingL,
                    AppTheme.spacingXS, AppTheme.spacingL, AppTheme.spacingM),
                child: Text(
                  '${tracks.length} morceaux · ${mix.artistsSummary}',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingL),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => playAll(context, tracks),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Jouer'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentPrimary),
                    ),
                    const SizedBox(width: AppTheme.spacingS),
                    OutlinedButton.icon(
                      onPressed: () => playShuffled(context, tracks),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Aléatoire'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Trier',
                      icon: Icon(
                        Icons.sort_rounded,
                        color: _sort != null
                            ? AppTheme.accentPrimary
                            : AppTheme.textSecondary,
                      ),
                      onPressed: () async {
                        final choice =
                            await showTrackSortSheet(context, current: _sort);
                        if (choice != null) {
                          setState(() => _sort = choice.option);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              Expanded(
                child: Stack(
                  children: [
                    TrackListScrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: tracks.length,
                        itemBuilder: (context, i) => KeyedSubtree(
                          key: _locator.keyFor(tracks[i].id),
                          child: ForYouListRow(
                            track: tracks[i],
                            onTap: () => openPlayer(context,
                                track: tracks[i], tracks: tracks),
                          ),
                        ),
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
