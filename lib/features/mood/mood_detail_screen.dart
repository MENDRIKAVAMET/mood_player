import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';
import '../../models/track.dart';
import '../../widgets/app_header.dart';
import '../../providers/audio_provider.dart' show currentTrackIdProvider;
import '../../providers/track_provider.dart' show TrackSortOption;
import '../../widgets/track_list_tools.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/track_options_sheet.dart';
import '../player/player_screen.dart';

/// Detailed mood screen showing all tracks for a specific mood
class MoodDetailScreen extends ConsumerStatefulWidget {
  final MoodType mood;
  final List<Track> tracks;

  const MoodDetailScreen({
    super.key,
    required this.mood,
    required this.tracks,
  });

  @override
  ConsumerState<MoodDetailScreen> createState() => _MoodDetailScreenState();
}

class _MoodDetailScreenState extends ConsumerState<MoodDetailScreen> {
  final ScrollController _scroll = ScrollController();
  late final TrackListLocator _locator =
      TrackListLocator(controller: _scroll);
  TrackSortOption? _sort;

  MoodType get mood => widget.mood;

  List<Track> get tracks =>
      _sort == null ? widget.tracks : sortTracks(widget.tracks, _sort!);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = this.tracks;
    final moodColors = MoodColors.forMood(mood);
    final currentId = ref.watch(currentTrackIdProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              moodColors.gradientStart,
              moodColors.gradientEnd,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header
              _buildHeader(context, moodColors),

              // Mood info
              _buildMoodInfo(moodColors),

              const SizedBox(height: AppTheme.spacingL),

              // Track count
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingXL,
                ),
                child: Row(
                  children: [
                    Text(
                      '${tracks.length} morceau${tracks.length > 1 ? 'x' : ''}',
                      style: AppTheme.bodyLarge.copyWith(
                        color: moodColors.primary,
                      ),
                    ),
                    const Spacer(),
                    // Tout lire / Aléatoire / Trier
                    TrackListActionBar(
                      tracks: tracks,
                      sort: _sort,
                      color: moodColors.primary,
                      onSort: (c) => setState(() => _sort = c.option),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingL),

              // Track list
              Expanded(
                child: tracks.isEmpty
                    ? _buildEmptyState(moodColors)
                    : Stack(
                        children: [
                          TrackListScrollbar(
                            controller: _scroll,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.only(
                                bottom: AppTheme.spacingXXXL,
                              ),
                              itemCount: tracks.length,
                              itemBuilder: (context, index) {
                                final track = tracks[index];
                                void open() => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PlayerScreen(
                                          track: track,
                                          tracks: tracks,
                                          initialIndex: index,
                                        ),
                                      ),
                                    );
                                return KeyedSubtree(
                                  key: _locator.keyFor(track.id),
                                  child: TrackTile(
                                    track: track,
                                    index: index,
                                    isPlaying: currentId == track.id.toString(),
                                    onTap: open,
                                    onPlay: open,
                                    onMore: () => showTrackOptionsSheet(
                                        context, ref, track),
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
      ).animate().fadeIn(
            duration: AppTheme.animSlow,
          ),
    );
  }

  Widget _buildHeader(BuildContext context, MoodColors moodColors) {
    return AppHeader(
      title: mood.displayName,
      showBack: true,
      backIcon: Icons.arrow_back_ios_new_rounded,
      actions: [
        SizedBox(
          width: 44,
          height: 44,
          child: Icon(mood.iconData, size: 24, color: moodColors.primary),
        ),
      ],
    );
  }

  Widget _buildMoodInfo(MoodColors moodColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingXL,
      ),
      child: Row(
        children: [
          // Color indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: moodColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ambiance ${mood.displayName}',
                style: AppTheme.titleLarge.copyWith(
                  color: moodColors.primary,
                ),
              ),
              Text(
                _getMoodDescription(mood),
                style: AppTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(MoodColors moodColors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: moodColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                mood.iconData,
                size: 36,
                color: moodColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingL),
          Text(
            'Aucun morceau',
            style: AppTheme.headlineMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Ajoutez des morceaux pour cette ambiance',
            style: AppTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _getMoodDescription(MoodType mood) {
    switch (mood) {
      case MoodType.energetic:
        return 'Musique dynamique et entraînante';
      case MoodType.chill:
        return 'Moments de détente et de calme';
      case MoodType.melancholic:
        return 'Émotions profondes et nostalgiques';
      case MoodType.festive:
        return 'Ambiance de fête et de joie';
      case MoodType.romantic:
        return 'Moments tendres et intimes';
      case MoodType.concentration:
        return 'Focus et productivité';
      case MoodType.motivating:
        return 'Inspiration et motivation';
      case MoodType.sad:
        return 'Mélancolie et réflexion';
      case MoodType.evangelical:
        return 'Louange, adoration et musique chrétienne';
      case MoodType.angry:
        return 'Colère et défouloir';
      case MoodType.nostalgic:
        return 'Souvenirs et retour vers le passé';
      case MoodType.dark:
        return 'Ambiance sombre, intense et tendue';
      case MoodType.sleep:
        return 'Pour s\'endormir en douceur';
      case MoodType.funny:
        return 'Humour et second degré';
      case MoodType.roadtrip:
        return 'Voyage et évasion sur la route';
      case MoodType.spiritual:
        return 'Méditation et pleine conscience';
      case MoodType.classical:
        return 'Instrumental savant et contemplatif';
      case MoodType.unknown:
        return 'Découvrir cette ambiance';
    }
  }
}
