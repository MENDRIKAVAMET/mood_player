import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/mood_suggestions_provider.dart';
import '../../providers/track_provider.dart' show TrackSortOption;
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/app_header.dart';
import '../../widgets/foryou_list_row.dart';
import '../../widgets/suggestion_mix_card.dart' show TrackMixTint;
import '../../widgets/track_artwork.dart';
import '../../widgets/track_list_tools.dart';

/// Contenu d'un mix : ses 20 morceaux, avec lecture dans l'ordre ou en
/// aléatoire.
class SuggestionMixScreen extends ConsumerStatefulWidget {
  final TrackMix mix;

  const SuggestionMixScreen({super.key, required this.mix});

  @override
  ConsumerState<SuggestionMixScreen> createState() => _SuggestionMixScreenState();
}

class _SuggestionMixScreenState extends ConsumerState<SuggestionMixScreen> {
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
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                title: mix.title,
                showBack: true,
              ),
              _MixHero(mix: mix, count: tracks.length),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingL),
                child: Row(
                  children: [
                    _PlayPill(
                      color: mix.tint,
                      onTap: () => playAll(context, tracks),
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
                            onPlay: () =>
                                togglePlayTrack(ref, tracks[i], tracks),
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

/// En-tête d'un mix : collage 2x2 des pochettes, sous-titre, nombre de
/// morceaux et artistes, le tout teinté de la couleur du mix.
class _MixHero extends StatelessWidget {
  final TrackMix mix;
  final int count;

  const _MixHero({required this.mix, required this.count});

  @override
  Widget build(BuildContext context) {
    final tint = mix.tint;
    final covers = mix.tracks.take(4).toList();
    const size = 104.0;
    const cell = (size - 2) / 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingXS,
        AppTheme.spacingL,
        AppTheme.spacingL,
      ),
      child: Row(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint.withValues(alpha: 0.7), AppTheme.backgroundCard],
              ),
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: 0.35),
                  blurRadius: 22,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  for (final t in covers)
                    TrackArtwork(
                      track: t,
                      size: cell,
                      radius: 0,
                      placeholderFontSize: 18,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingL),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    mix.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall.copyWith(
                      color: tint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                Text(
                  '$count morceaux',
                  style: AppTheme.titleLarge
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  mix.artistsSummary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton « Jouer » en pastille dégradée, aux couleurs du mix.
class _PlayPill extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _PlayPill({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: Ink(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            gradient: LinearGradient(
              colors: [color, Color.lerp(color, AppTheme.brandBottom, 0.45)!],
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 4),
              Text(
                'Jouer',
                style: AppTheme.labelLarge.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
