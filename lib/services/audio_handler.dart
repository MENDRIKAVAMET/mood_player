import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'storage_service.dart';

/// Repeat mode enum (renamed to avoid clashing with Flutter's own RepeatMode)
enum PlayerRepeatMode {
  off,
  all,
  one,
}

class MoodAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final List<MediaItem> _queue = [];
  final List<MediaItem> _originalQueue = []; // Store original order for unshuffle
  final _repeatModeController = StreamController<PlayerRepeatMode>.broadcast();
  final _shuffleModeController = StreamController<bool>.broadcast();
  final _likeChangedController =
      StreamController<(int trackId, bool liked)>.broadcast();
  final StorageService _storageService = StorageService();
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  bool _shuffleMode = false;

  /// Stream of repeat mode changes
  Stream<PlayerRepeatMode> get repeatModeStream => _repeatModeController.stream;

  /// Stream of shuffle mode changes
  Stream<bool> get shuffleModeStream => _shuffleModeController.stream;

  /// Fires whenever the "like" notification button toggles a track, so the
  /// rest of the app (track list, player screen heart icon) can stay in
  /// sync without polling.
  Stream<(int trackId, bool liked)> get likeChangedStream =>
      _likeChangedController.stream;

  /// Stream of the current track duration
  Stream<Duration> get durationStream =>
      _player.durationStream.map((d) => d ?? Duration.zero);

  /// Current repeat mode
  PlayerRepeatMode get repeatMode => _repeatMode;

  /// Current shuffle mode
  bool get shuffleMode => _shuffleMode;

  MoodAudioHandler() {
    _init();
  }

  /// Notification "like" button, dedicated close (X) icon/label - moved to
  /// the far right - in place of the old plain "Stop" both in icon and
  /// position, and the play/pause + skip controls in between.
  static final _likeControl = MediaControl.custom(
    androidIcon: 'mipmap/ic_favorite_border',
    label: 'Aimer',
    name: 'toggleLike',
  );
  static final _likedControl = MediaControl.custom(
    androidIcon: 'mipmap/ic_favorite',
    label: 'Retirer des favoris',
    name: 'toggleLike',
  );
  static const _closeControl = MediaControl(
    androidIcon: 'mipmap/ic_close',
    label: 'Fermer',
    action: MediaAction.stop,
  );

  List<MediaControl> _buildControls(bool isPlaying, bool isLiked) {
    return [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      isLiked ? _likedControl : _likeControl,
      // Far right, as requested: was a plain "Stop" icon before, now a
      // dedicated close (X) icon/label. Same underlying stop action, so
      // behavior (closes the notification and playback) is unchanged.
      _closeControl,
    ];
  }

  /// Re-pushes playbackState with fresh controls, e.g. after the like
  /// button changes the current track's liked state - the icon needs to
  /// flip immediately rather than waiting for the next player state event.
  void _pushControls() {
    final isPlaying = _player.playing;
    final isLiked = mediaItem.value?.extras?['isLiked'] == true;
    playbackState.add(playbackState.value.copyWith(
      controls: _buildControls(isPlaying, isLiked),
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'toggleLike') {
      await _toggleLikeCurrentTrack();
      return;
    }
    return super.customAction(name, extras);
  }

  /// Flips the current track's liked state from the notification button:
  /// persists it, updates the notification's own media item so the icon
  /// flips immediately, and broadcasts the change so any open screen
  /// (player, track list) can stay in sync without polling.
  Future<void> _toggleLikeCurrentTrack() async {
    final current = mediaItem.value;
    if (current == null) return;

    final trackId = int.tryParse(current.id);
    if (trackId == null) return;

    final wasLiked = current.extras?['isLiked'] == true;
    final newLiked = !wasLiked;

    try {
      await _storageService.setTrackLiked(trackId, newLiked);
    } catch (e) {
      // ignore: avoid_print
      print('MoodAudioHandler: failed to persist like for $trackId: $e');
      return;
    }

    final updatedExtras = {...?current.extras, 'isLiked': newLiked};
    final updatedItem = current.copyWith(extras: updatedExtras);
    mediaItem.add(updatedItem);

    final queueIndex = _queue.indexWhere((item) => item.id == current.id);
    if (queueIndex >= 0) {
      _queue[queueIndex] = updatedItem;
      queue.add(List.unmodifiable(_queue));
    }

    _pushControls();
    _likeChangedController.add((trackId, newLiked));
  }

  void _init() {
    // Listen to player state changes
    _player.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = _mapProcessingState(playerState.processingState);
      final isLiked = mediaItem.value?.extras?['isLiked'] == true;

      playbackState.add(playbackState.value.copyWith(
        controls: _buildControls(isPlaying, isLiked),
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        // Previous / play-pause / next stay in the compact (collapsed)
        // notification view; like and close only show in the expanded one.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
    }, onError: _handlePlaybackError);

    // Listen to position changes
    _player.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
    }, onError: _handlePlaybackError);

    // Listen to sequence state for auto-advance
    _player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed) {
        _handleTrackComplete();
      }
    }, onError: _handlePlaybackError);

    // just_audio/ExoPlayer surfaces genuine playback failures (corrupt file,
    // revoked content:// permission, unsupported codec, network hiccup for
    // streamed sources, etc.) here rather than as a synchronous throw. Left
    // unhandled this is an uncaught stream error that kills the isolate -
    // exactly the crash-on-play bug. Treat it as non-fatal: log it, reset
    // to an idle/stopped state, and let the user try another track.
    _player.playbackEventStream.listen((_) {}, onError: _handlePlaybackError);
  }

  /// Handle a playback error surfaced asynchronously by just_audio. Never
  /// lets a bad track take down the whole app - just stops cleanly so the
  /// user can pick something else.
  void _handlePlaybackError(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('MoodAudioHandler: playback stream error: $error\n$stackTrace');
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  /// Handle track completion based on repeat mode
  void _handleTrackComplete() {
    switch (_repeatMode) {
      case PlayerRepeatMode.one:
        // Restart the same track
        _player.seek(Duration.zero);
        _player.play();
        break;
      case PlayerRepeatMode.all:
      case PlayerRepeatMode.off:
        // Use skipToNext which already handles wrap-around logic
        skipToNext();
        break;
    }
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } catch (e, st) {
      _handlePlaybackError(e, st);
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set repeat mode (renamed: BaseAudioHandler already has a setRepeatMode)
  void setPlayerRepeatMode(PlayerRepeatMode mode) {
    _repeatMode = mode;
    _repeatModeController.add(mode);
  }

  /// Cycle through repeat modes: off -> all -> one -> off
  void cycleRepeatMode() {
    switch (_repeatMode) {
      case PlayerRepeatMode.off:
        setPlayerRepeatMode(PlayerRepeatMode.all);
        break;
      case PlayerRepeatMode.all:
        setPlayerRepeatMode(PlayerRepeatMode.one);
        break;
      case PlayerRepeatMode.one:
        setPlayerRepeatMode(PlayerRepeatMode.off);
        break;
    }
  }

  /// Toggle shuffle mode
  void toggleShuffle() {
    _shuffleMode = !_shuffleMode;
    _shuffleModeController.add(_shuffleMode);
    
    if (_shuffleMode) {
      _shuffleQueue();
    } else {
      _unshuffleQueue();
    }
  }

  /// Shuffle the queue while keeping current track as first
  void _shuffleQueue() {
    if (_queue.isEmpty) return;
    
    // Find current track
    final currentItem = mediaItem.value;
    final currentIndex = _queue.indexWhere(
      (item) => item.id == currentItem?.id,
    );
    
    // Remove current track from queue, shuffle the rest
    final currentTrack = currentIndex >= 0 ? _queue.removeAt(currentIndex) : null;
    _queue.shuffle();
    
    // Put current track at the beginning
    if (currentTrack != null) {
      _queue.insert(0, currentTrack);
    }
    
    queue.add(List.unmodifiable(_queue));
  }

  /// Restore original queue order
  void _unshuffleQueue() {
    if (_originalQueue.isEmpty) return;
    
    // Find current track to keep it playing
    final currentItem = mediaItem.value;
    
    // Restore original order
    _queue.clear();
    _queue.addAll(_originalQueue);
    _originalQueue.clear();
    
    // If we have a current track, ensure the reference is updated
    if (currentItem != null) {
      final newIndex = _queue.indexWhere(
        (item) => item.id == currentItem.id,
      );
      if (newIndex >= 0) {
        // Just update the reference without replaying
        mediaItem.add(_queue[newIndex]);
      }
    }
    
    queue.add(List.unmodifiable(_queue));
  }

  @override
  Future<void> skipToNext() async {
    final currentIndex = queue.value.indexWhere(
      (item) => item.id == mediaItem.value?.id,
    );
    
    int nextIndex = currentIndex + 1;
    
    if (nextIndex >= queue.value.length) {
      if (_repeatMode == PlayerRepeatMode.all && queue.value.isNotEmpty) {
        nextIndex = 0; // Wrap to beginning
      } else {
        return; // End of queue
      }
    }
    
    final nextItem = queue.value[nextIndex];
    await _playMediaItem(nextItem);
  }

  @override
  Future<void> skipToPrevious() async {
    final currentIndex = queue.value.indexWhere(
      (item) => item.id == mediaItem.value?.id,
    );
    
    int prevIndex = currentIndex - 1;
    
    if (prevIndex < 0) {
      if (_repeatMode == PlayerRepeatMode.all && queue.value.isNotEmpty) {
        prevIndex = queue.value.length - 1; // Wrap to end
      } else {
        return; // Beginning of queue
      }
    }
    
    final previousItem = queue.value[prevIndex];
    await _playMediaItem(previousItem);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < queue.value.length) {
      final item = queue.value[index];
      await _playMediaItem(item);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  /// Add a track to the queue and play it
  Future<void> addAndPlayTrack(Track track) async {
    final mediaItem = _trackToMediaItem(track);
    
    // Add to queue if not already present
    if (!_queue.contains(mediaItem)) {
      _queue.add(mediaItem);
      queue.add(List.unmodifiable(_queue));
    }
    
    // Play the track
    await _playMediaItem(mediaItem);
  }

  /// Replace the queue and play a track from a list at a given index
  Future<void> playTrackFromList(List<Track> tracks, int index) async {
    if (tracks.isEmpty || index < 0 || index >= tracks.length) return;
    
    // Replace the queue with the new list
    _queue.clear();
    _queue.addAll(tracks.map(_trackToMediaItem));
    
    // Always store the original order for unshuffle
    _originalQueue.clear();
    _originalQueue.addAll(_queue);
    
    queue.add(List.unmodifiable(_queue));
    
    // Play the track at the given index
    final mediaItem = _queue[index];
    await _playMediaItem(mediaItem);
  }

  /// Add multiple tracks to the queue
  Future<void> addTracksToQueue(List<Track> tracks) async {
    final mediaItems = tracks.map(_trackToMediaItem).toList();
    
    for (final item in mediaItems) {
      if (!_queue.contains(item)) {
        _queue.add(item);
      }
    }
    
    queue.add(List.unmodifiable(_queue));
  }

  /// Insère [track] juste après le morceau en cours de lecture, pour une
  /// lecture immédiate au morceau suivant sans perturber le reste de la
  /// file. Si rien ne joue, revient à un simple ajout en fin de file.
  Future<void> playNext(Track track) async {
    final item = _trackToMediaItem(track);

    // Un même morceau ne doit pas apparaître deux fois dans la file :
    // s'il y est déjà, on le déplace plutôt que de le dupliquer.
    _queue.removeWhere((existing) => existing.id == item.id);

    final currentItem = mediaItem.value;
    final currentIndex =
        currentItem != null ? _queue.indexWhere((e) => e.id == currentItem.id) : -1;

    if (currentIndex >= 0) {
      _queue.insert(currentIndex + 1, item);
    } else {
      _queue.add(item);
    }

    queue.add(List.unmodifiable(_queue));
  }

  /// Clear the queue
  Future<void> clearQueue() async {
    await _player.stop();
    _queue.clear();
    queue.add([]);
    mediaItem.add(null);
  }

  /// Remove a track from the queue by index
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final item = _queue[index];
    final currentItem = mediaItem.value;
    final wasPlaying = currentItem?.id == item.id;

    // Remove the item
    _queue.removeAt(index);

    // Update the queue stream
    queue.add(List.unmodifiable(_queue));

    // If the removed item was playing, play the next one or stop
    if (wasPlaying) {
      if (_queue.isEmpty) {
        // Queue is empty, stop playback
        await _player.stop();
        mediaItem.add(null);
      } else {
        // Play the next item at the same index (or first if at end)
        final nextIndex = index < _queue.length ? index : 0;
        await _playMediaItem(_queue[nextIndex]);
      }
    }
  }

  /// Reorder the queue
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;

    // Find the current playing track to update reference if needed
    final currentItem = mediaItem.value;
    final wasPlayingId = currentItem?.id;

    // Remove the item from old position
    final item = _queue.removeAt(oldIndex);

    // Insert at new position
    _queue.insert(newIndex, item);

    // Update the queue stream
    queue.add(List.unmodifiable(_queue));

    // If the moved item is the currently playing track, update the reference
    if (wasPlayingId == item.id) {
      mediaItem.add(item);
    }
  }

  /// Play a specific media item
  Future<void> _playMediaItem(MediaItem item) async {
    mediaItem.add(item);

    final uri = item.extras?['uri'] as String?;
    final filePath = item.extras?['filePath'] as String?;

    if (uri == null && filePath == null) return;

    try {
      Duration? duration;
      if (uri != null) {
        // Preferred: content:// URI from MediaStore. Required on Android
        // 10+ (scoped storage) since apps can't read another app's media
        // files by raw filesystem path, only through the ContentResolver.
        duration = await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
      } else {
        duration = await _player.setFilePath(filePath!);
      }

      // Reflect the real duration on the media item as soon as it's known,
      // so the UI (queue, notification) has it immediately rather than
      // waiting on the duration stream alone.
      if (duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }

      await _player.play();
    } catch (e, st) {
      // ignore: avoid_print
      print('MoodAudioHandler: failed to play "${item.title}": $e\n$st');
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
    }
  }

  /// Convertit une pochette (chemin local ou URL) en URI exploitable par
  /// la notification média.
  Uri? _artUriFor(String? cover) {
    if (cover == null || cover.isEmpty) return null;
    if (cover.startsWith('http://') || cover.startsWith('https://')) {
      return Uri.tryParse(cover);
    }
    final file = File(cover);
    return file.existsSync() ? Uri.file(cover) : null;
  }

  MediaItem _trackToMediaItem(Track track) {
    return MediaItem(
      id: track.id.toString(),
      title: track.title,
      artist: track.artist,
      album: track.album ?? '',
      duration: track.duration != null
          ? Duration(milliseconds: track.duration!)
          : null,
      // C'est ce champ, et lui seul, qui met la pochette sur l'écran
      // verrouillé et dans la notification de lecture. Android exige une
      // URI : le chemin local extrait des tags devient donc file://…,
      // une URL http passe telle quelle.
      artUri: _artUriFor(track.coverUrl),
      extras: {
        'filePath': track.filePath,
        'uri': track.uri,
        // Transporté ici aussi : le mini-lecteur reconstruit un Track à
        // partir du MediaItem, et artUri seul ne suffit pas à le lui
        // redonner.
        'coverUrl': track.coverUrl,
        'mood': track.mood?.displayName,
        'moodConfidence': track.moodConfidence,
        // Used by the notification's "like" button to persist/reflect the
        // right track's favorite state.
        'trackId': track.id,
        'isLiked': track.isLiked,
      },
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await super.onTaskRemoved();
  }

  Future<void> close() async {
    await _repeatModeController.close();
    await _shuffleModeController.close();
    await _likeChangedController.close();
    await _player.dispose();
  }
}

/// Initialize audio service
Future<MoodAudioHandler> initAudioService() async {
  return await AudioService.init<MoodAudioHandler>(
    builder: () => MoodAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.mood_player.audio',
      androidNotificationChannelName: 'Mood Player',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // A white-silhouette icon dedicated to the notification (Android
      // masks/tints small icons in the status bar - a full-color icon
      // like the launcher one renders as an ugly solid blob there).
      // Protected from ever being resource-shrunk away by
      // android/app/src/main/res/raw/keep.xml, since it's the underlying
      // resource resolving to a null/0 id that caused
      // "Invalid notification (no valid small icon)" here before.
      androidNotificationIcon: 'mipmap/ic_notification',
      notificationColor: Color(0xFF8A00FF),
      // Les pochettes extraites font 512 px ; les redescendre à 256 évite
      // qu'Android recharge et redimensionne une grosse bitmap à chaque
      // mise à jour de la notification.
      artDownscaleWidth: 256,
      artDownscaleHeight: 256,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
}