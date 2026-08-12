import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// Opens a modal sheet letting the user multi-select tracks to add to a
/// custom mood. Tracks already in the mood are pre-checked (re-confirming
/// just leaves them as-is). Returns the list of newly-selected tracks, or
/// null if cancelled.
Future<void> showAddTracksToMoodSheet(
  BuildContext context,
  WidgetRef ref, {
  required int moodId,
  required Set<int> alreadyInMood,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
    ),
    builder: (context) => _AddTracksSheet(moodId: moodId, alreadyInMood: alreadyInMood),
  );
}

class _AddTracksSheet extends ConsumerStatefulWidget {
  final int moodId;
  final Set<int> alreadyInMood;

  const _AddTracksSheet({required this.moodId, required this.alreadyInMood});

  @override
  ConsumerState<_AddTracksSheet> createState() => _AddTracksSheetState();
}

class _AddTracksSheetState extends ConsumerState<_AddTracksSheet> {
  final Set<int> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final allTracks = ref.watch(trackProvider).tracks;
    final filtered = _query.isEmpty
        ? allTracks
        : allTracks.where((t) {
            final q = _query.toLowerCase();
            return t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.spacingM),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                child: Row(
                  children: [
                    Text('Ajouter des morceaux', style: AppTheme.headlineMedium),
                    const Spacer(),
                    if (_selected.isNotEmpty)
                      Text(
                        '${_selected.length} sélectionné(s)',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.accentPrimary),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                child: TextField(
                  style: AppTheme.bodyMedium,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                    prefixIcon: Icon(Icons.search, color: AppTheme.textTertiary, size: 20),
                    filled: true,
                    fillColor: AppTheme.backgroundCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusM),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final track = filtered[index];
                    final alreadyThere = widget.alreadyInMood.contains(track.id);
                    final checked = alreadyThere || _selected.contains(track.id);

                    return CheckboxListTile(
                      value: checked,
                      enabled: !alreadyThere,
                      activeColor: AppTheme.accentPrimary,
                      checkColor: Colors.black,
                      title: Text(
                        track.title,
                        style: AppTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        alreadyThere ? '${track.artist} · déjà ajouté' : track.artist,
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: alreadyThere
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(track.id);
                                } else {
                                  _selected.remove(track.id);
                                }
                              });
                            },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentPrimary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusM),
                      ),
                    ),
                    onPressed: _selected.isEmpty
                        ? null
                        : () async {
                            final tracksToAdd =
                                allTracks.where((t) => _selected.contains(t.id)).toList();
                            await ref
                                .read(customMoodProvider.notifier)
                                .addTracks(widget.moodId, tracksToAdd);
                            if (context.mounted) Navigator.pop(context);
                          },
                    child: Text(
                      _selected.isEmpty ? 'Sélectionner des morceaux' : 'Ajouter (${_selected.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
