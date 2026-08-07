import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/storage_service.dart';
import '../services/gemini_service.dart';

// Service providers
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
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

  TrackNotifier(this._storageService, this._geminiService) 
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
  return TrackNotifier(storageService, geminiService);
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