import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// Shows the "..." options sheet for a single [track]. Shared between
/// every place a track is listed (library, home, search, custom moods)
/// so all of them get the same working actions instead of each screen
/// reinventing (or half-implementing) its own.
void showTrackOptionsSheet(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  VoidCallback? onShowQueue,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _TrackOptionsSheet(track: track, onShowQueue: onShowQueue),
  );
}

class _TrackOptionsSheet extends ConsumerWidget {
  final Track track;
  final VoidCallback? onShowQueue;

  const _TrackOptionsSheet({required this.track, this.onShowQueue});

  Future<void> _addToQueue(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    final handlerAsync = ref.read(audioHandlerProvider);
    final handler = handlerAsync.valueOrNull;
    if (handler == null) return;
    await handler.addTracksToQueue([track]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${track.title}" ajouté à la file d\'attente')),
      );
    }
  }

  Future<void> _toggleLike(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    await ref.read(trackProvider.notifier).toggleLike(track);
  }

  Future<void> _share(BuildContext context) async {
    Navigator.pop(context);
    final text = '${track.title} - ${track.artist}';
    final path = track.filePath;
    try {
      if (path != null && path.isNotEmpty) {
        await Share.shareXFiles([XFile(path)], text: text);
      } else {
        await Share.share(text);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Partage impossible : $e')),
        );
      }
    }
  }

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddToPlaylistSheet(track: track),
    );
  }

  void _showInfo(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: Text(track.title, style: AppTheme.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Artiste', value: track.artist),
            if (track.album != null && track.album!.isNotEmpty)
              _InfoRow(label: 'Album', value: track.album!),
            _InfoRow(label: 'Durée', value: track.durationFormatted),
            if (track.mood != null)
              _InfoRow(label: 'Mood', value: track.moodDisplayName),
            if (track.filePath != null)
              _InfoRow(label: 'Fichier', value: track.filePath!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: const Text('Retirer ce morceau ?'),
        content: Text(
          '"${track.title}" sera retiré de la bibliothèque de l\'app '
          '(le fichier reste sur ton appareil).',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(trackProvider.notifier).deleteTrack(track.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiked = track.isLiked;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppTheme.spacingM),
              decoration: BoxDecoration(
                color: AppTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            if (onShowQueue != null)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text('Voir la file d\'attente', style: AppTheme.bodyLarge),
                onTap: () {
                  Navigator.pop(context);
                  onShowQueue!();
                },
              ),
            ListTile(
              leading: Icon(
                isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isLiked ? Colors.redAccent : null,
              ),
              title: Text(
                isLiked ? 'Retirer des favoris' : 'Ajouter aux favoris',
                style: AppTheme.bodyLarge,
              ),
              onTap: () => _toggleLike(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text('Ajouter à la file d\'attente', style: AppTheme.bodyLarge),
              onTap: () => _addToQueue(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.library_add_rounded),
              title: Text('Ajouter à une playlist', style: AppTheme.bodyLarge),
              onTap: () => _addToPlaylist(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: Text('Partager', style: AppTheme.bodyLarge),
              onTap: () => _share(context),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text('Informations', style: AppTheme.bodyLarge),
              onTap: () => _showInfo(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text(
                'Retirer de la bibliothèque',
                style: AppTheme.bodyLarge.copyWith(color: Colors.redAccent),
              ),
              onTap: () => _confirmDelete(context, ref),
            ),
            const SizedBox(height: AppTheme.spacingM),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary)),
          Text(value, style: AppTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Playlist picker: lists existing playlists to add the track to, plus a
/// "create new" option. Uses the Isar-backed Playlist CRUD that already
/// existed in StorageService but had no UI wired to it.
class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  final Track track;

  const _AddToPlaylistSheet({required this.track});

  @override
  ConsumerState<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  List<Playlist>? _playlists;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(storageServiceProvider);
    final playlists = await storage.getAllPlaylists();
    if (mounted) setState(() => _playlists = playlists);
  }

  Future<void> _addTo(Playlist playlist) async {
    final storage = ref.read(storageServiceProvider);
    final trackId = widget.track.id;
    if (!playlist.trackIds.contains(trackId)) {
      playlist.trackIds = [...playlist.trackIds, trackId];
      await storage.savePlaylist(playlist);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ajouté à "${playlist.name}"')),
      );
    }
  }

  Future<void> _createAndAdd() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: const Text('Nouvelle playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nom de la playlist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final storage = ref.read(storageServiceProvider);
    final playlist = Playlist()
      ..name = name
      ..trackIds = [widget.track.id]
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();
    await storage.savePlaylist(playlist);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist "$name" créée')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: const BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppTheme.spacingM),
              decoration: BoxDecoration(
                color: AppTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Text('Ajouter à une playlist', style: AppTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text('Nouvelle playlist', style: AppTheme.bodyLarge),
              onTap: _createAndAdd,
            ),
            const Divider(height: 1),
            Flexible(
              child: _playlists == null
                  ? const Padding(
                      padding: EdgeInsets.all(AppTheme.spacingXL),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _playlists!.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppTheme.spacingXL),
                          child: Text(
                            'Aucune playlist pour l\'instant.',
                            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _playlists!.length,
                          itemBuilder: (context, index) {
                            final playlist = _playlists![index];
                            return ListTile(
                              leading: const Icon(Icons.playlist_play_rounded),
                              title: Text(playlist.name, style: AppTheme.bodyLarge),
                              subtitle: Text('${playlist.trackCount} morceaux'),
                              onTap: () => _addTo(playlist),
                            );
                          },
                        ),
            ),
            const SizedBox(height: AppTheme.spacingM),
          ],
        ),
      ),
    );
  }
}
