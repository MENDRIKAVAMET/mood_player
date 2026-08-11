import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../models/track.dart';
import '../services/storage_service.dart';
import '../services/gemini_service.dart';
import '../services/library_scan_service.dart';

// Service providers
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

final libraryScanServiceProvider = Provider<LibraryScanService>((ref) {
  return LibraryScanService();
});

// Track state
class TrackState {
  final List<Track> tracks;
  final List<Track> filteredTracks;
  final MoodType? selectedMood;
  final String searchQuery;
  final bool isLoading;
  final String? error;

  const TrackState({
    this.tracks = const [],
    this.filteredTracks = const [],
    this.selectedMood,
    this.searchQuery = '',
    this.isLoading = false,
    this.error,
  });

  TrackState copyWith({
    List<Track>? tracks,
    List<Track>? filteredTracks,
    MoodType? selectedMood,
    String? searchQuery,
    bool? isLoading,
    String? error,
  }) {
    return TrackState(
      tracks: tracks ?? this.tracks,
      filteredTracks: filteredTracks ?? this.filteredTracks,
      selectedMood: selectedMood ?? this.selectedMood,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Track notifier
class TrackNotifier extends StateNotifier<TrackState> {
  final StorageService _storageService;
  final GeminiService _geminiService;
  final LibraryScanService _libraryScanService;

  TrackNotifier(this._storageService, this._geminiService, this._libraryScanService)
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
        state = state.copyWith(
          error: 'Autorisation d\'accès à la musique refusée. '
              'Activez-la dans les paramètres pour scanner votre bibliothèque.',
        );
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
          final track = Track()
            ..title = song.title.isNotEmpty ? song.title : 'Titre inconnu'
            ..artist = (song.artist != null && song.artist!.isNotEmpty)
                ? song.artist!
                : 'Artiste inconnu'
            ..album = song.album
            ..filePath = filePath
            ..uri = song.uri
            ..duration = song.duration
            ..createdAt = now
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

  /// Classify a track using Gemini
  Future<void> classifyTrack(Track track) async {
    if (track.isClassified) return;
    
    try {
      final result = await _geminiService.classifyTrack(track);
      
      if (!result.hasError) {
        track.mood = result.mood;
        track.moodConfidence = result.confidence;
        track.lastClassified = DateTime.now();
        await _storageService.saveTrack(track);
        await loadTracks();
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Erreur lors de la classification: $e',
      );
    }
  }

  /// Classify all unclassified tracks
  Future<void> classifyAllUnclassified() async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final unclassifiedTracks = await _storageService.getUnclassifiedTracks();
      
      for (final track in unclassifiedTracks) {
        await classifyTrack(track);
      }
      
      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de la classification en lot: $e',
      );
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
  final geminiService = ref.watch(geminiServiceProvider);
  final libraryScanService = ref.watch(libraryScanServiceProvider);
  return TrackNotifier(storageService, geminiService, libraryScanService);
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