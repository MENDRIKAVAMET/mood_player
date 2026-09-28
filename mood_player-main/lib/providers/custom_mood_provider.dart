import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/custom_mood.dart';
import '../models/track.dart';
import 'track_provider.dart' show storageServiceProvider;

class CustomMoodState {
  final List<CustomMood> moods;
  final bool isLoading;
  final String? error;

  const CustomMoodState({
    this.moods = const [],
    this.isLoading = false,
    this.error,
  });

  CustomMoodState copyWith({
    List<CustomMood>? moods,
    bool? isLoading,
    String? error,
  }) {
    return CustomMoodState(
      moods: moods ?? this.moods,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class CustomMoodNotifier extends StateNotifier<CustomMoodState> {
  final Ref _ref;

  CustomMoodNotifier(this._ref) : super(const CustomMoodState());

  Future<void> loadMoods() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final storage = _ref.read(storageServiceProvider);
      final moods = await storage.getAllCustomMoods();
      state = state.copyWith(moods: moods, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors du chargement des moods: $e',
      );
    }
  }

  Future<void> createMood({
    required String name,
    String icon = 'music',
    int colorValue = 0xFF7C6CFF,
  }) async {
    try {
      final storage = _ref.read(storageServiceProvider);
      await storage.createCustomMood(name: name, icon: icon, colorValue: colorValue);
      await loadMoods();
    } catch (e) {
      state = state.copyWith(error: 'Erreur lors de la création du mood: $e');
    }
  }

  Future<void> renameMood(CustomMood mood, {String? name, String? icon, int? colorValue}) async {
    try {
      final storage = _ref.read(storageServiceProvider);
      if (name != null) mood.name = name;
      if (icon != null) mood.icon = icon;
      if (colorValue != null) mood.colorValue = colorValue;
      await storage.saveCustomMood(mood);
      await loadMoods();
    } catch (e) {
      state = state.copyWith(error: 'Erreur lors de la modification du mood: $e');
    }
  }

  Future<void> deleteMood(int moodId) async {
    try {
      final storage = _ref.read(storageServiceProvider);
      await storage.deleteCustomMood(moodId);
      await loadMoods();
    } catch (e) {
      state = state.copyWith(error: 'Erreur lors de la suppression du mood: $e');
    }
  }

  Future<void> addTrack(int moodId, Track track, {double percentage = 100}) async {
    try {
      final storage = _ref.read(storageServiceProvider);
      await storage.addTrackToCustomMood(moodId, track.id, percentage: percentage);
      await loadMoods();
    } catch (e) {
      state = state.copyWith(error: 'Erreur lors de l\'ajout du morceau: $e');
    }
  }

  Future<void> addTracks(int moodId, List<Track> tracks, {double percentage = 100}) async {
    try {
      final storage = _ref.read(storageServiceProvider);
      for (final track in tracks) {
        await storage.addTrackToCustomMood(moodId, track.id, percentage: percentage);
      }
      await loadMoods();
    } catch (e) {
      state = state.copyWith(error: 'Erreur lors de l\'ajout des morceaux: $e');
    }
  }

  Future<void> removeTrack(int moodId, int trackId) async {
    try {
      final storage = _ref.read(storageServiceProvider);
      await storage.removeTrackFromCustomMood(moodId, trackId);
      await loadMoods();
    } catch (e) {
      state = state.copyWith(error: 'Erreur lors de la suppression du morceau: $e');
    }
  }

  Future<void> setPercentage(int moodId, int trackId, double percentage) async {
    try {
      final storage = _ref.read(storageServiceProvider);
      await storage.setTrackPercentageInMood(moodId, trackId, percentage);
      await loadMoods();
    } catch (e) {
      state = state.copyWith(error: 'Erreur lors de la mise à jour du pourcentage: $e');
    }
  }
}

final customMoodProvider = StateNotifierProvider<CustomMoodNotifier, CustomMoodState>((ref) {
  return CustomMoodNotifier(ref);
});

/// Tracks (with their percentage) inside a given custom mood, sorted by
/// percentage descending by default.
final customMoodTracksProvider =
    FutureProvider.family<List<(Track, double)>, int>((ref, moodId) async {
  // Re-run whenever the moods list changes (e.g. a track was added/removed).
  ref.watch(customMoodProvider);
  final storage = ref.read(storageServiceProvider);
  final entries = await storage.getTracksInCustomMood(moodId);
  entries.sort((a, b) => b.$2.compareTo(a.$2));
  return entries;
});
