import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/playlist.dart';
import '../../providers/providers.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

/// Queue screen showing all tracks in the current playback queue
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  late List<MediaItem> _localQueue;
  bool _isReordering = false;

  @override
  void initState() {
    super.initState();
    _localQueue = [];
  }

  void _syncWithQueue(List<MediaItem> items) {
    if (!_isReordering && mounted) {
      setState(() {
        _localQueue = List.from(items);
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _localQueue.removeAt(oldIndex);
      _localQueue.insert(newIndex, item);
    });

    // Apply to actual queue
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.reorderQueue(oldIndex, newIndex);
    });
  }

  void _toggleReorderMode() {
    setState(() {
      _isReordering = !_isReordering;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final queue = ref.watch(queueProvider);

    // Sync local queue with actual queue when not reordering
    queue.whenData((items) => _syncWithQueue(items));

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), AppTheme.backgroundPrimary],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(context),

              // Queue info with reorder button
              _buildQueueInfo(currentTrack.valueOrNull),

              const SizedBox(height: AppTheme.spacingL),

              // Queue list
              Expanded(
                child: _localQueue.isEmpty
                    ? _buildEmptyState()
                    : _buildReorderableList(currentTrack.valueOrNull),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingM,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.backgroundCardElevated.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 24,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          // Title
          Text('File d\'attente', style: AppTheme.headlineMedium),
          // Action buttons
          Row(
            children: [
              // Save as playlist button
              if (_localQueue.isNotEmpty)
                GestureDetector(
                  onTap: _showSavePlaylistDialog,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundCardElevated.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.playlist_add_rounded,
                      size: 20,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: AppTheme.spacingS),
              // Reorder button
              GestureDetector(
                onTap: _toggleReorderMode,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isReordering
                        ? AppTheme.accentPrimary.withOpacity(0.2)
                        : AppTheme.backgroundCardElevated.withOpacity(0.5),
                    shape: BoxShape.circle,
                    border: _isReordering
                        ? Border.all(
                            color: AppTheme.accentPrimary.withOpacity(0.5),
                            width: 1,
                          )
                        : null,
                  ),
                  child: Icon(
                    _isReordering
                        ? Icons.check_rounded
                        : Icons.drag_handle_rounded,
                    size: 20,
                    color: _isReordering
                        ? AppTheme.accentPrimary
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueInfo(MediaItem? currentTrack) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXL),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.accentPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Text(
            '${_localQueue.length} morceau${_localQueue.length > 1 ? 'x' : ''}',
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          if (_isReordering) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingS,
                vertical: AppTheme.spacingXXS,
              ),
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusS),
              ),
              child: Text(
                'Mode réorganisation',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.accentPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.accentPrimary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              size: 40,
              color: AppTheme.accentPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingL),
          Text(
            'File d\'attente vide',
            style: AppTheme.headlineMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Lancez la lecture d\'une liste\npour remplir la file',
            style: AppTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReorderableList(MediaItem? currentTrack) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingS,
      ),
      itemCount: _localQueue.length,
      onReorder: _isReordering ? _onReorder : (oldIndex, newIndex) {},
      proxyDecorator: (child, index, animation) {
        final scale = 1.0 + (animation.value * 0.05);
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      itemBuilder: (context, index) {
        final item = _localQueue[index];
        final isCurrentTrack = currentTrack?.id == item.id;

        return _buildQueueItem(
          key: ValueKey(item.id),
          item: item,
          index: index,
          isCurrentTrack: isCurrentTrack,
          onTap: () => _playQueueItem(index),
        );
      },
    );
  }

  Widget _buildQueueItem({
    required Key key,
    required MediaItem item,
    required int index,
    required bool isCurrentTrack,
    required VoidCallback onTap,
  }) {
    return Dismissible(
      key: key,
      direction: _isReordering
          ? DismissDirection.none
          : DismissDirection.endToStart,
      onDismissed: (direction) => _removeFromQueue(index),
      background: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
        decoration: BoxDecoration(
          color: AppTheme.accentError.withOpacity(0.2),
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppTheme.spacingXL),
        child: Icon(
          Icons.delete_rounded,
          color: AppTheme.accentError,
          size: 28,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
        decoration: BoxDecoration(
          color: isCurrentTrack
              ? AppTheme.accentPrimary.withOpacity(0.15)
              : AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          border: Border.all(
            color: isCurrentTrack
                ? AppTheme.accentPrimary.withOpacity(0.3)
                : AppTheme.border.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingM,
            vertical: AppTheme.spacingXS,
          ),
          leading: _isReordering
              ? Icon(
                  Icons.drag_handle_rounded,
                  color: AppTheme.textTertiary,
                  size: 24,
                )
              : isCurrentTrack
              ? Icon(
                  Icons.equalizer_rounded,
                  color: AppTheme.accentPrimary,
                  size: 20,
                )
              : SizedBox(
                  width: 24,
                  child: Text(
                    '${index + 1}',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
          title: Text(
            item.title,
            style: AppTheme.bodyLarge.copyWith(
              color: isCurrentTrack
                  ? AppTheme.accentPrimary
                  : AppTheme.textPrimary,
              fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            item.artist,
            style: AppTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.extras?['mood'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingS,
                    vertical: AppTheme.spacingXXS,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusS),
                  ),
                  child: Text(
                    '${item.extras!['mood']}',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.accentPrimary,
                    ),
                  ),
                ),
              if (!_isReordering)
                IconButton(
                  icon: Icon(
                    Icons.play_circle_outline_rounded,
                    color: isCurrentTrack
                        ? AppTheme.accentPrimary
                        : AppTheme.textSecondary,
                  ),
                  onPressed: onTap,
                ),
            ],
          ),
          onTap: _isReordering ? null : onTap,
        ),
      ),
    ).animate().fadeIn(
      duration: AppTheme.animNormal,
      delay: Duration(milliseconds: 30 * index),
    );
  }

  void _playQueueItem(int index) {
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.skipToQueueItem(index);
    });
  }

  void _removeFromQueue(int index) {
    // Update local queue immediately for UI responsiveness
    setState(() {
      _localQueue.removeAt(index);
    });

    // Apply to actual queue
    final audioHandlerAsync = ref.read(audioHandlerProvider);
    audioHandlerAsync.whenData((handler) {
      handler.removeFromQueue(index);
    });
  }

  void _showSavePlaylistDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Sauvegarder en playlist', style: AppTheme.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_localQueue.length} morceau${_localQueue.length > 1 ? 'x' : ''}',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            TextField(
              controller: nameController,
              autofocus: true,
              style: AppTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Nom de la playlist',
                hintStyle: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textTertiary,
                ),
                filled: true,
                fillColor: AppTheme.backgroundPrimary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: const BorderSide(
                    color: AppTheme.accentPrimary,
                    width: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => _savePlaylist(nameController.text),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
              ),
            ),
            child: Text(
              'Sauvegarder',
              style: AppTheme.bodyLarge.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }  Future<void> _savePlaylist(String name) async {
    if (name.trim().isEmpty) return;
    
    Navigator.pop(context); // Close dialog
    
    try {
      // Create playlist with track IDs
      final playlist = Playlist()
        ..name = name.trim()
        ..trackIds = _localQueue.map((item) {
          // Extract track ID from MediaItem.id (stored as string)
          return int.tryParse(item.id) ?? 0;
        }).where((id) => id > 0).toList() // Filter out invalid IDs
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();
      
      // Save to database
      final storage = StorageService();
      await storage.savePlaylist(playlist);
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Playlist "${playlist.name}" sauvegardée',
              style: AppTheme.bodyMedium.copyWith(color: Colors.white),
            ),
            backgroundColor: AppTheme.accentSuccess,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            margin: const EdgeInsets.all(AppTheme.spacingM),
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de la sauvegarde',
              style: AppTheme.bodyMedium.copyWith(color: Colors.white),
            ),
            backgroundColor: AppTheme.accentError,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            margin: const EdgeInsets.all(AppTheme.spacingM),
          ),
        );
      }
    }
  }
}
