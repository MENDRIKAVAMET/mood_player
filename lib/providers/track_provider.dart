import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../models/track.dart';
import '../services/storage_service.dart';
import '../services/groq_service.dart';
import '../services/library_scan_service.dart';

// Service providers
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final groqServiceProvider = Provider<GroqService>((ref) {
  return GroqService();
});

final libraryScanServiceProvider = Provider<LibraryScanService>((ref) {
  return LibraryScanService();
});

/// Available ways to sort the track list.
enum TrackSortOption {
  nameAsc,
  nameDesc,
  dateNewest,
  dateOldest,
}

extension TrackSortOptionLabel on TrackSortOption {
  String get label {
    switch (this) {
      case TrackSortOption.nameAsc:
        return 'Nom (A → Z)';
      case TrackSortOption.nameDesc:
        return 'Nom (Z → A)';
      case TrackSortOption.dateNewest:
        return 'Plus récent';
      case TrackSortOption.dateOldest:
        return 'Plus ancien';
    }
  }
}

// Track state
class TrackState {
  final List<Track> tracks;
  final List<Track> filteredTracks;
  final MoodType? selectedMood;
  final String searchQuery;
  final bool isLoading;
  final String? error;
  final TrackSortOption sortOption;
  final int? minDurationSeconds;

  /// Non-null while a batch classification is in progress; tracks how many
  /// of [classifyTotal] tracks have been processed so far, for the
  /// progress indicator.
  final int? classifyProgress;
  final int? classifyTotal;

  /// Short status line shown under the progress bar (e.g. waiting out a
  /// rate limit). Null when there's nothing special to report.
  final String? classifyStatusMessage;

  const TrackState({
    this.tracks = const [],
    this.filteredTracks = const [],
    this.selectedMood,
    this.searchQuery = '',
    this.isLoading = false,
    this.error,
    this.sortOption = TrackSortOption.dateNewest,
    this.minDurationSeconds,
    this.classifyProgress,
    this.classifyTotal,
    this.classifyStatusMessage,
  });

  bool get isClassifying => classifyTotal != null;

  TrackState copyWith({
    List<Track>? tracks,
    List<Track>? filteredTracks,
    MoodType? selectedMood,
    String? searchQuery,
    bool? isLoading,
    String? error,
    TrackSortOption? sortOption,
    int? minDurationSeconds,
    bool clearMinDurationSeconds = false,
    int? classifyProgress,
    int? classifyTotal,
    bool clearClassifyProgress = false,
    String? classifyStatusMessage,
    bool clearClassifyStatusMessage = false,
  }) {
    return TrackState(
      tracks: tracks ?? this.tracks,
      filteredTracks: filteredTracks ?? this.filteredTracks,
      selectedMood: selectedMood ?? this.selectedMood,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sortOption: sortOption ?? this.sortOption,
      minDurationSeconds: clearMinDurationSeconds
          ? null
          : (minDurationSeconds ?? this.minDurationSeconds),
      classifyProgress: clearClassifyProgress
          ? null
          : (classifyProgress ?? this.classifyProgress),
      classifyTotal: clearClassifyProgress
          ? null
          : (classifyTotal ?? this.classifyTotal),
      classifyStatusMessage: clearClassifyProgress || clearClassifyStatusMessage
          ? null
          : (classifyStatusMessage ?? this.classifyStatusMessage),
    );
  }
}

// Track notifier
class TrackNotifier extends StateNotifier<TrackState> {
  final StorageService _storageService;
  final GroqService _groqService;
  final LibraryScanService _libraryScanService;

  TrackNotifier(this._storageService, this._groqService, this._libraryScanService)
      : super(const TrackState());

  /// Load all tracks from storage
  Future<void> loadTracks() async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final tracks = await _storageService.getAllTracks();
      state = state.copyWith(
        tracks: tracks,
        filteredTracks: tracks,
        isLoading: false,
      );
      _applyFilters();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors du chargement des morceaux: $e',
      );
    }
  }

  /// Scan the device's entire audio library (every format the OS indexes),
  /// merge the results into local storage (updating already-known tracks
  /// with fresh metadata/duration while preserving their mood
  /// classification), then reload. Runs on every app open.
  Future<void> scanAndLoadTracks() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _libraryScanService.scan();

      if (!result.permissionGranted) {
        // No permission: fall back to whatever is already stored locally.
        await loadTracks();
        final permanentlyDenied =
            await _libraryScanService.isPermissionPermanentlyDenied();
        state = state.copyWith(
          error: permanentlyDenied
              ? 'Autorisation d\'accès à la musique définitivement refusée. '
                  'Activez-la dans les paramètres de l\'application.'
              : 'Autorisation d\'accès à la musique refusée. '
                  'Activez-la dans les paramètres pour scanner votre bibliothèque.',
        );
        return;
      }

      if (result.songs.isEmpty) {
        // Permission is granted but the OS reports no audio at all. Say so
        // explicitly - otherwise this is indistinguishable from a bug,
        // since the screen just shows an empty list either way.
        await loadTracks();
        if (state.tracks.isEmpty) {
          state = state.copyWith(
            error: 'Aucun fichier audio trouvé sur cet appareil. '
                'Si vous avez de la musique, elle n\'est peut-être pas encore '
                'indexée par le système.',
          );
        }
        return;
      }

      final existingTracks = await _storageService.getAllTracks();
      final byFilePath = <String, Track>{
        for (final t in existingTracks)
          if (t.filePath != null) t.filePath!: t,
      };

      final now = DateTime.now();
      final toSave = <Track>[];

      for (final SongModel song in result.songs) {
        final filePath = song.data;
        if (filePath.isEmpty) continue;

        final existing = byFilePath[filePath];
        if (existing != null) {
          // Update metadata/duration for an already-known track, keep its
          // mood classification and creation date intact.
          existing
            ..title = song.title.isNotEmpty ? song.title : existing.title
            ..artist = (song.artist != null && song.artist!.isNotEmpty)
                ? song.artist!
                : existing.artist
            ..album = song.album ?? existing.album
            ..duration = song.duration ?? existing.duration
            ..uri = song.uri ?? existing.uri
            ..updatedAt = now;
          toSave.add(existing);
        } else {
          // Use the device's actual "date added" from MediaStore rather
          // than the scan time. Using DateTime.now() here made every
          // track added in the same scan (e.g. right after a fresh
          // install, or after StorageService's corruption-recovery reset)
          // get virtually the same timestamp, which made "Plus récent" /
          // "Plus ancien" sorting look broken since there was nothing
          // meaningful left to sort by. The real per-file date from the OS
          // stays meaningful and stable regardless of when we happen to
          // scan it.
          final deviceDateAdded = song.dateAdded;
          final createdAt = deviceDateAdded != null
              ? DateTime.fromMillisecondsSinceEpoch(deviceDateAdded * 1000)
              : now;

          final track = Track()
            ..title = song.title.isNotEmpty ? song.title : 'Titre inconnu'
            ..artist = (song.artist != null && song.artist!.isNotEmpty)
                ? song.artist!
                : 'Artiste inconnu'
            ..album = song.album
            ..filePath = filePath
            ..uri = song.uri
            ..duration = song.duration
            ..createdAt = createdAt
            ..updatedAt = now;
          toSave.add(track);
        }
      }

      if (toSave.isNotEmpty) {
        await _storageService.saveTracks(toSave);
      }

      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors du scan de la bibliothèque: $e',
      );
    }
  }

  /// Add a new track
  Future<void> addTrack(Track track) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _storageService.saveTrack(track);
      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de l\'ajout du morceau: $e',
      );
    }
  }

  /// Toggles the liked status of [track] and persists it, updating the
  /// in-memory state without a full library reload.
  Future<void> toggleLike(Track track) async {
    final newValue = !track.isLiked;
    track.isLiked = newValue;
    try {
      await _storageService.setTrackLiked(track.id, newValue);
      final updatedTracks = [
        for (final t in state.tracks) if (t.id == track.id) track else t,
      ];
      state = state.copyWith(tracks: updatedTracks);
      _applyFilters();
    } catch (e) {
      track.isLiked = !newValue;
      state = state.copyWith(error: 'Erreur lors de la mise à jour du favori: $e');
    }
  }

  /// Classify a single track (kept for completeness/manual use elsewhere -
  /// batch classification below is the path actually used for bulk work).
  Future<void> classifyTrack(Track track) async {
    if (track.isClassified) return;
    await _classifyChunk([track], maxRateLimitRetries: 5);
  }

  /// Sends one Groq request classifying every track in [chunk] together,
  /// applies the results, and retries the whole chunk automatically if
  /// Groq responds with a rate limit (429).
  Future<void> _classifyChunk(List<Track> chunk, {required int maxRateLimitRetries}) async {
    var attempt = 0;
    while (true) {
      try {
        final results = await _groqService.classifyTracksBatch(chunk);

        final updatedTracks = List<Track>.from(state.tracks);
        String? lastError;
        final toSave = <Track>[];

        for (var i = 0; i < chunk.length; i++) {
          final track = chunk[i];
          final result = results[i];

          if (!result.hasError) {
            track.mood = result.mood;
            track.moodConfidence = result.confidence;
            track.lastClassified = DateTime.now();
            toSave.add(track);

            final index = updatedTracks.indexWhere((t) => t.id == track.id);
            if (index != -1) updatedTracks[index] = track;
          } else {
            lastError = 'Erreur lors de la classification de "${track.title}": ${result.error}';
          }
        }

        if (toSave.isNotEmpty) {
          await _storageService.saveTracks(toSave);
        }

        state = state.copyWith(
          tracks: updatedTracks,
          error: lastError,
          clearClassifyStatusMessage: true,
        );
        _applyFilters();
        return;
      } on GroqRateLimitException catch (e) {
        attempt++;
        if (attempt > maxRateLimitRetries) {
          state = state.copyWith(
            error: 'Limite de requêtes Groq atteinte pour ce lot de '
                '${chunk.length} morceaux, nouvelle tentative nécessaire plus tard.',
            clearClassifyStatusMessage: true,
          );
          return;
        }

        // Count down visibly instead of freezing with no feedback.
        var remaining = e.retryAfter.inSeconds.clamp(1, 120);
        while (remaining > 0) {
          state = state.copyWith(
            error: state.error,
            classifyStatusMessage:
                'Limite Groq atteinte, reprise dans ${remaining}s…',
          );
          await Future.delayed(const Duration(seconds: 1));
          remaining--;
        }
        // loop back around and retry this same chunk
      } catch (e) {
        state = state.copyWith(
          error: 'Erreur lors de la classification du lot: $e',
          clearClassifyStatusMessage: true,
        );
        return;
      }
    }
  }

  /// Classify all unclassified tracks, sent in batches (default 50 tracks
  /// per Groq request) instead of one request per track - cuts the number
  /// of API calls by ~50x, which matters a lot against free-tier rate
  /// limits when classifying a whole library.
  Future<void> classifyAllUnclassified({int batchSize = 50}) async {
    state = state.copyWith(error: null);

    try {
      final unclassifiedTracks = await _storageService.getUnclassifiedTracks();
      if (unclassifiedTracks.isEmpty) return;

      state = state.copyWith(
        classifyProgress: 0,
        classifyTotal: unclassifiedTracks.length,
      );

      var processed = 0;
      for (var start = 0; start < unclassifiedTracks.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, unclassifiedTracks.length);
        final chunk = unclassifiedTracks.sublist(start, end);

        await _classifyChunk(chunk, maxRateLimitRetries: 5);
        processed += chunk.length;
        state = state.copyWith(classifyProgress: processed, error: state.error);

        // Small pause between batches - with 50 tracks/request there are
        // far fewer calls overall, but this still keeps us clear of
        // Groq's free-tier rate limit if batches are small/numerous.
        if (end < unclassifiedTracks.length) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Erreur lors de la classification en lot: $e',
      );
    } finally {
      // Always clear the progress indicator, whether every track
      // succeeded, some failed, or the whole batch blew up.
      state = state.copyWith(clearClassifyProgress: true);
    }
  }

  /// Filter tracks by mood
  void filterByMood(MoodType? mood) {
    state = state.copyWith(selectedMood: mood);
    _applyFilters();
  }

  /// Search tracks
  void searchTracks(String query) {
    state = state.copyWith(searchQuery: query);
    _applyFilters();
  }

  /// Change how the "Tous les morceaux" list is ordered
  void setSortOption(TrackSortOption option) {
    state = state.copyWith(sortOption: option);
    _applyFilters();
  }

  /// Hide tracks shorter than [seconds]. Pass null to remove the filter.
  void setMinDurationFilter(int? seconds) {
    if (seconds == null) {
      state = state.copyWith(clearMinDurationSeconds: true);
    } else {
      state = state.copyWith(minDurationSeconds: seconds);
    }
    _applyFilters();
  }

  /// Apply current filters
  void _applyFilters() {
    List<Track> filtered = List.from(state.tracks);
    
    // Filter by mood
    if (state.selectedMood != null) {
      filtered = filtered.where((track) => track.mood == state.selectedMood).toList();
    }
    
    // Filter by search query
    if (state.searchQuery.isNotEmpty) {
      final query = state.searchQuery.toLowerCase();
      filtered = filtered.where((track) =>
        track.title.toLowerCase().contains(query) ||
        track.artist.toLowerCase().contains(query) ||
        (track.album?.toLowerCase().contains(query) ?? false)
      ).toList();
    }

    // Hide short tracks (e.g. ringtones/notification sounds picked up by
    // the device scan)
    final minSeconds = state.minDurationSeconds;
    if (minSeconds != null && minSeconds > 0) {
      final minMs = minSeconds * 1000;
      filtered = filtered
          .where((track) => (track.duration ?? 0) >= minMs)
          .toList();
    }

    // Sort
    switch (state.sortOption) {
      case TrackSortOption.nameAsc:
        filtered.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case TrackSortOption.nameDesc:
        filtered.sort((a, b) =>
            b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case TrackSortOption.dateNewest:
        filtered.sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
        break;
      case TrackSortOption.dateOldest:
        filtered.sort((a, b) => (a.createdAt ?? DateTime(0))
            .compareTo(b.createdAt ?? DateTime(0)));
        break;
    }
    
    state = state.copyWith(filteredTracks: filtered);
  }

  /// Delete a track
  Future<void> deleteTrack(int id) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _storageService.deleteTrack(id);
      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de la suppression: $e',
      );
    }
  }

  /// Clear all tracks
  Future<void> clearAllTracks() async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _storageService.clearAllTracks();
      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de la suppression: $e',
      );
    }
  }
}

// Track provider
final trackProvider = StateNotifierProvider<TrackNotifier, TrackState>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  final groqService = ref.watch(groqServiceProvider);
  final libraryScanService = ref.watch(libraryScanServiceProvider);
  return TrackNotifier(storageService, groqService, libraryScanService);
});

// Filtered tracks provider
final filteredTracksProvider = Provider<List<Track>>((ref) {
  final trackState = ref.watch(trackProvider);
  return trackState.filteredTracks;
});

// Tracks by mood provider
final tracksByMoodProvider = Provider.family<List<Track>, MoodType>((ref, mood) {
  final trackState = ref.watch(trackProvider);
  return trackState.tracks.where((track) => track.mood == mood).toList();
});

// Track count by mood provider
final trackCountByMoodProvider = Provider<Map<MoodType, int>>((ref) {
  final trackState = ref.watch(trackProvider);
  final counts = <MoodType, int>{};
  
  for (final mood in MoodType.values) {
    if (mood == MoodType.unknown) continue;
    counts[mood] = trackState.tracks.where((track) => track.mood == mood).length;
  }
  
  return counts;
});

// Current mood filter provider
final currentMoodFilterProvider = Provider<MoodType?>((ref) {
  return ref.watch(trackProvider).selectedMood;
});