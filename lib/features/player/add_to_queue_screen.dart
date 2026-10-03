import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/track_artwork.dart';

/// Écran de sélection de morceaux à ajouter à la file d'attente en cours,
/// ouvert depuis le bouton "+" de [QueueScreen]. Coche une ou plusieurs
/// pistes de la bibliothèque, puis les ajoute d'un coup via
/// `addTracksToQueue` sans toucher au reste de la file.
class AddToQueueScreen extends ConsumerStatefulWidget {
  const AddToQueueScreen({super.key});

  @override
  ConsumerState<AddToQueueScreen> createState() => _AddToQueueScreenState();
}

class _AddToQueueScreenState extends ConsumerState<AddToQueueScreen> {
  final Set<int> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Track> _filteredTracks(List<Track> tracks) {
    if (_query.isEmpty) return tracks;
    final q = _query.toLowerCase();
    return tracks
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q),
        )
        .toList();
  }

  void _toggleTrack(Track track) {
    setState(() {
      if (_selectedIds.contains(track.id)) {
        _selectedIds.remove(track.id);
      } else {
        _selectedIds.add(track.id);
      }
    });
  }

  void _toggleSelectAll(List<Track> visibleTracks) {
    final allSelected = visibleTracks.isNotEmpty &&
        visibleTracks.every((t) => _selectedIds.contains(t.id));
    setState(() {
      if (allSelected) {
        for (final t in visibleTracks) {
          _selectedIds.remove(t.id);
        }
      } else {
        for (final t in visibleTracks) {
          _selectedIds.add(t.id);
        }
      }
    });
  }

  Future<void> _confirmSelection(List<Track> allTracks) async {
    if (_selectedIds.isEmpty) return;
    final selected = allTracks.where((t) => _selectedIds.contains(t.id)).toList();

    final handler = await ref.read(audioHandlerProvider.future);
    await handler.addTracksToQueue(selected);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final allTracks = ref.watch(trackProvider).tracks;
    final visibleTracks = _filteredTracks(allTracks);
    final allVisibleSelected = visibleTracks.isNotEmpty &&
        visibleTracks.every((t) => _selectedIds.contains(t.id));

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: AppTheme.spacingM),
              _buildSelectAllRow(visibleTracks, allVisibleSelected),
              const SizedBox(height: AppTheme.spacingS),
              Expanded(
                child: visibleTracks.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingL,
                          vertical: AppTheme.spacingS,
                        ),
                        itemCount: visibleTracks.length,
                        itemBuilder: (context, index) {
                          final track = visibleTracks[index];
                          return _buildTrackRow(track);
                        },
                      ),
              ),
              _buildBottomBar(allTracks),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: _searching ? null : 'Ajouter de la musique',
      titleWidget: _searching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textPrimary),
              cursorColor: AppTheme.accentPrimary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Rechercher un titre, un artiste...',
                hintStyle: AppTheme.bodyLarge,
              ),
              onChanged: (value) => setState(() => _query = value),
            )
          : null,
      showBack: true,
      actions: [
        AppHeaderButton(
          icon: _searching ? Icons.close_rounded : Icons.search_rounded,
          tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
          onTap: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchController.clear();
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildSelectAllRow(List<Track> visibleTracks, bool allSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        onTap: visibleTracks.isEmpty ? null : () => _toggleSelectAll(visibleTracks),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
          child: Row(
            children: [
              Text('Tout sélectionner', style: AppTheme.bodyLarge.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              )),
              const Spacer(),
              _buildCheckCircle(allSelected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckCircle(bool selected) {
    return AnimatedContainer(
      duration: AppTheme.animFast,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppTheme.accentPrimary : Colors.transparent,
        border: Border.all(
          color: selected ? AppTheme.accentPrimary : AppTheme.border,
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );
  }

  Widget _buildTrackRow(Track track) {
    final selected = _selectedIds.contains(track.id);
    return GestureDetector(
      onTap: () => _toggleTrack(track),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingXS,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accentPrimary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: Row(
          children: [
            TrackArtwork(track: track, size: 48, radius: AppTheme.radiusS),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: AppTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingM),
            _buildCheckCircle(selected),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        _query.isEmpty ? 'Aucun morceau dans la bibliothèque' : 'Aucun résultat',
        style: AppTheme.bodyMedium,
      ),
    );
  }

  Widget _buildBottomBar(List<Track> allTracks) {
    final count = _selectedIds.length;
    return AnimatedSwitcher(
      duration: AppTheme.animNormal,
      child: count == 0
          ? const SizedBox.shrink()
          : Padding(
              key: const ValueKey('add-bar'),
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingL,
                AppTheme.spacingS,
                AppTheme.spacingL,
                AppTheme.spacingL,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _confirmSelection(allTracks),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusL),
                    ),
                  ),
                  child: Text(
                    'Ajouter $count morceau${count > 1 ? 'x' : ''}',
                    style: AppTheme.bodyLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
