import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/custom_mood.dart';
import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_tracks_to_mood_sheet.dart';
import '../../widgets/mood_editor_dialog.dart';
import '../player/player_screen.dart';

enum _MoodTrackSort { percentageDesc, percentageAsc, nameAsc }

/// Detail screen for a user-created [CustomMood]: lists its tracks sorted
/// by match percentage, lets the user add/remove tracks and edit each
/// track's percentage, rename/delete the mood, and play straight from here.
class CustomMoodDetailScreen extends ConsumerStatefulWidget {
  final CustomMood mood;

  const CustomMoodDetailScreen({super.key, required this.mood});

  @override
  ConsumerState<CustomMoodDetailScreen> createState() => _CustomMoodDetailScreenState();
}

class _CustomMoodDetailScreenState extends ConsumerState<CustomMoodDetailScreen> {
  _MoodTrackSort _sort = _MoodTrackSort.percentageDesc;

  @override
  Widget build(BuildContext context) {
    // Keep showing the latest version of this mood (name/icon/color may
    // have been edited) as moods list refreshes.
    final moods = ref.watch(customMoodProvider).moods;
    final mood = moods.firstWhere(
      (m) => m.id == widget.mood.id,
      orElse: () => widget.mood,
    );
    final color = Color(mood.colorValue);

    final entriesAsync = ref.watch(customMoodTracksProvider(mood.id));

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, mood, color),
            Expanded(
              child: entriesAsync.when(
                data: (entries) {
                  if (entries.isEmpty) {
                    return _buildEmptyState(color);
                  }
                  final sorted = _sortEntries(entries);
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: AppTheme.spacingS, bottom: 100),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final (track, percentage) = sorted[index];
                      return _MoodTrackRow(
                        track: track,
                        percentage: percentage,
                        color: color,
                        onTap: () {
                          final tracks = sorted.map((e) => e.$1).toList();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                track: track,
                                tracks: tracks,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                        onEditPercentage: () => _showPercentageDialog(mood.id, track, percentage),
                        onRemove: () => ref
                            .read(customMoodProvider.notifier)
                            .removeTrack(mood.id, track.id),
                      );
                    },
                  );
                },
                loading: () => const Center(child: SizedBox.shrink()),
                error: (e, _) => Center(
                  child: Text(
                    'Erreur: $e',
                    style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: color,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () async {
          final entries = entriesAsync.valueOrNull ?? [];
          await showAddTracksToMoodSheet(
            context,
            ref,
            moodId: mood.id,
            alreadyInMood: entries.map((e) => e.$1.id).toSet(),
          );
        },
      ),
    );
  }

  List<(Track, double)> _sortEntries(List<(Track, double)> entries) {
    final list = List<(Track, double)>.from(entries);
    switch (_sort) {
      case _MoodTrackSort.percentageDesc:
        list.sort((a, b) => b.$2.compareTo(a.$2));
        break;
      case _MoodTrackSort.percentageAsc:
        list.sort((a, b) => a.$2.compareTo(b.$2));
        break;
      case _MoodTrackSort.nameAsc:
        list.sort((a, b) => a.$1.title.toLowerCase().compareTo(b.$1.title.toLowerCase()));
        break;
    }
    return list;
  }

  Widget _buildHeader(BuildContext context, CustomMood mood, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingM,
        AppTheme.spacingS,
        AppTheme.spacingL,
        AppTheme.spacingS,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: AppTheme.spacingXS),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Center(child: Text(mood.icon, style: const TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: AppTheme.spacingS),
              Expanded(
                child: Text(
                  mood.name,
                  style: AppTheme.headlineMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: AppTheme.textSecondary),
                color: AppTheme.backgroundSecondary,
                onSelected: (value) async {
                  if (value == 'sort_desc') {
                    setState(() => _sort = _MoodTrackSort.percentageDesc);
                  } else if (value == 'sort_asc') {
                    setState(() => _sort = _MoodTrackSort.percentageAsc);
                  } else if (value == 'sort_name') {
                    setState(() => _sort = _MoodTrackSort.nameAsc);
                  } else if (value == 'edit') {
                    final result = await showMoodEditorDialog(context, existing: mood);
                    if (result != null) {
                      await ref.read(customMoodProvider.notifier).renameMood(
                            mood,
                            name: result.$1,
                            icon: result.$2,
                            colorValue: result.$3,
                          );
                    }
                  } else if (value == 'delete') {
                    final confirmed = await _confirmDelete(context, mood.name);
                    if (confirmed && context.mounted) {
                      await ref.read(customMoodProvider.notifier).deleteMood(mood.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'sort_desc',
                    child: _menuRow(Icons.arrow_downward_rounded, 'Trier: % décroissant',
                        active: _sort == _MoodTrackSort.percentageDesc),
                  ),
                  PopupMenuItem(
                    value: 'sort_asc',
                    child: _menuRow(Icons.arrow_upward_rounded, 'Trier: % croissant',
                        active: _sort == _MoodTrackSort.percentageAsc),
                  ),
                  PopupMenuItem(
                    value: 'sort_name',
                    child: _menuRow(Icons.sort_by_alpha_rounded, 'Trier: nom',
                        active: _sort == _MoodTrackSort.nameAsc),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'edit',
                    child: _menuRow(Icons.edit_outlined, 'Modifier le mood'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _menuRow(Icons.delete_outline_rounded, 'Supprimer le mood',
                        color: Colors.redAccent),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 2),
            child: Text(
              '${mood.trackCount} morceau${mood.trackCount > 1 ? 'x' : ''}',
              style: AppTheme.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, {bool active = false, Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? (active ? AppTheme.accentPrimary : AppTheme.textSecondary)),
        const SizedBox(width: AppTheme.spacingS),
        Text(
          label,
          style: AppTheme.bodyMedium.copyWith(
            color: color ?? (active ? AppTheme.accentPrimary : null),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add_rounded, size: 48, color: color.withValues(alpha: 0.5)),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              'Aucun morceau dans ce mood',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              'Touche "Ajouter" pour en insérer',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusL)),
        title: Text('Supprimer "$name" ?', style: AppTheme.headlineMedium),
        content: Text(
          'Le mood sera supprimé. Les morceaux eux-mêmes ne sont pas affectés.',
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showPercentageDialog(int moodId, Track track, double currentPercentage) {
    var value = currentPercentage;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.backgroundSecondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusL)),
              title: Text(
                track.title,
                style: AppTheme.headlineMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${value.round()}%',
                    style: AppTheme.headlineMedium.copyWith(color: AppTheme.accentPrimary),
                  ),
                  Slider(
                    value: value,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: AppTheme.accentPrimary,
                    onChanged: (v) => setState(() => value = v),
                  ),
                  Text(
                    'À quel point ce morceau correspond à ce mood',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(customMoodProvider.notifier).setPercentage(moodId, track.id, value);
                    Navigator.pop(context);
                  },
                  child: Text('Enregistrer', style: TextStyle(color: AppTheme.accentPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MoodTrackRow extends StatelessWidget {
  final Track track;
  final double percentage;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onEditPercentage;
  final VoidCallback onRemove;

  const _MoodTrackRow({
    required this.track,
    required this.percentage,
    required this.color,
    required this.onTap,
    required this.onEditPercentage,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('mood_track_${track.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
        margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingL,
          vertical: AppTheme.spacingXS,
        ),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
      ),
      onDismissed: (_) => onRemove(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingL,
            vertical: AppTheme.spacingXS,
          ),
          padding: const EdgeInsets.all(AppTheme.spacingM),
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Icon(Icons.music_note_rounded, color: color, size: 20),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: AppTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingS),
              GestureDetector(
                onTap: onEditPercentage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    '${percentage.round()}%',
                    style: AppTheme.labelSmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
