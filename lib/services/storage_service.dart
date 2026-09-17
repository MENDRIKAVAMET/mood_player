import 'dart:convert';
import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../models/custom_mood.dart';

class StorageService {
  static Isar? _isar;
  
  /// Initialize Isar database
  static Future<void> initialize() async {
    if (_isar != null) return;
    
    final dir = await getApplicationDocumentsDirectory();
    try {
      _isar = await Isar.open(
        [TrackSchema, PlaylistSchema, CustomMoodSchema],
        directory: dir.path,
      );
    } catch (e) {
      // A crash mid-write can leave the Isar file corrupted, which then
      // fails to open on every subsequent launch (not just the one right
      // after the crash) - permanently soft-bricking the app with no way
      // back in for the user. Self-heal by wiping the local database and
      // retrying once. This loses the local library index, but the app
      // rebuilds it from the device's media store on next scan, which is
      // far better than the app refusing to open at all.
      // ignore: avoid_print
      print('StorageService: Isar.open failed ($e), resetting database and retrying');
      await _deleteDatabaseFiles(dir.path);
      _isar = await Isar.open(
        [TrackSchema, PlaylistSchema, CustomMoodSchema],
        directory: dir.path,
      );
    }
  }

  static Future<void> _deleteDatabaseFiles(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.contains('.isar')) {
        try {
          await entity.delete();
        } catch (_) {
          // Best effort - if a file can't be deleted, Isar.open's retry
          // will surface its own error and the fallback screen still
          // catches it.
        }
      }
    }
  }

  /// Get all tracks
  Future<List<Track>> getAllTracks() async {
    final isar = await _getIsar();
    final tracks = await isar.tracks.where().findAll();
    await _applyLikedStatus(tracks);
    return tracks;
  }

  /// Get tracks by mood
  Future<List<Track>> getTracksByMood(MoodType mood) async {
    final isar = await _getIsar();
    final tracks = await isar.tracks
        .where()
        .filter()
        .moodIndexEqualTo(mood.index)
        .findAll();
    await _applyLikedStatus(tracks);
    return tracks;
  }

  /// Get unclassified tracks (mood is null)
  Future<List<Track>> getUnclassifiedTracks() async {
    final isar = await _getIsar();
    final tracks = await isar.tracks
        .where()
        .filter()
        .moodIndexIsNull()
        .findAll();
    await _applyLikedStatus(tracks);
    return tracks;
  }

  /// Search tracks by title or artist
  Future<List<Track>> searchTracks(String query) async {
    final isar = await _getIsar();
    final lowerQuery = query.toLowerCase();
    
    final tracks = await isar.tracks
        .where()
        .filter()
        .titleContains(lowerQuery)
        .or()
        .artistContains(lowerQuery)
        .findAll();
    await _applyLikedStatus(tracks);
    return tracks;
  }

  /// Get a single track by ID
  Future<Track?> getTrackById(int id) async {
    final isar = await _getIsar();
    final track = await isar.tracks.get(id);
    if (track != null) {
      track.isLiked = await isTrackLiked(track.id);
    }
    return track;
  }

  /// Applies the persisted liked status (kept outside Isar, see
  /// [setTrackLiked]) onto each track in [tracks], in place.
  Future<void> _applyLikedStatus(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final likedIds = await getLikedTrackIds();
    for (final track in tracks) {
      track.isLiked = likedIds.contains(track.id);
    }
  }


  /// Insert or update a track
  Future<void> saveTrack(Track track) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.tracks.put(track);
    });
  }

  static Set<int>? _likedIdsCache;

  Future<File> _likedIdsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/liked_tracks.json');
  }

  Future<Set<int>> _loadLikedIds() async {
    if (_likedIdsCache != null) return _likedIdsCache!;
    try {
      final file = await _likedIdsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content) as List<dynamic>;
        _likedIdsCache = decoded.map((e) => e as int).toSet();
      } else {
        _likedIdsCache = <int>{};
      }
    } catch (_) {
      _likedIdsCache = <int>{};
    }
    return _likedIdsCache!;
  }

  Future<void> _saveLikedIds(Set<int> ids) async {
    _likedIdsCache = ids;
    final file = await _likedIdsFile();
    await file.writeAsString(jsonEncode(ids.toList()));
  }

  /// Returns whether [trackId] is marked as a favorite.
  Future<bool> isTrackLiked(int trackId) async {
    final ids = await _loadLikedIds();
    return ids.contains(trackId);
  }

  /// Returns the set of all favorite track IDs.
  Future<Set<int>> getLikedTrackIds() async {
    return Set<int>.from(await _loadLikedIds());
  }

  /// Sets the favorite status of [trackId], persisted across app restarts.
  Future<void> setTrackLiked(int trackId, bool liked) async {
    final ids = await _loadLikedIds();
    if (liked) {
      ids.add(trackId);
    } else {
      ids.remove(trackId);
    }
    await _saveLikedIds(ids);
  }

  /// Insert or update multiple tracks
  Future<void> saveTracks(List<Track> tracks) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.tracks.putAll(tracks);
    });
  }

  /// Delete a track
  Future<void> deleteTrack(int id) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.tracks.delete(id);
    });
  }

  /// Delete multiple tracks
  Future<void> deleteTracks(List<int> ids) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.tracks.deleteAll(ids);
    });
  }

  /// Get tracks count by mood
  Future<Map<MoodType, int>> getTrackCountByMood() async {
    final isar = await _getIsar();
    final counts = <MoodType, int>{};
    
    for (final mood in MoodType.values) {
      if (mood == MoodType.unknown) continue;
      
      final count = await isar.tracks
          .where()
          .filter()
          .moodIndexEqualTo(mood.index)
          .count();
      
      counts[mood] = count;
    }
    
    return counts;
  }

  /// Get total track count
  Future<int> getTrackCount() async {
    final isar = await _getIsar();
    return await isar.tracks.count();
  }

  /// Get classified tracks count
  Future<int> getClassifiedTracksCount() async {
    final isar = await _getIsar();
    return await isar.tracks
        .where()
        .filter()
        .moodIndexIsNotNull()
        .count();
  }

  /// Clear all tracks
  Future<void> clearAllTracks() async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.tracks.clear();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // PLAYLIST METHODS
  // ═══════════════════════════════════════════════════════════════

  /// Get all playlists
  Future<List<Playlist>> getAllPlaylists() async {
    final isar = await _getIsar();
    return await isar.playlists.where().findAll();
  }

  /// Get a playlist by ID
  Future<Playlist?> getPlaylistById(int id) async {
    final isar = await _getIsar();
    return await isar.playlists.get(id);
  }

  /// Get a playlist with its tracks loaded
  Future<(Playlist, List<Track>)?> getPlaylistWithTracks(int id) async {
    final isar = await _getIsar();
    final playlist = await isar.playlists.get(id);
    if (playlist == null) return null;

    final tracks = <Track>[];
    for (final trackId in playlist.trackIds) {
      final track = await isar.tracks.get(trackId);
      if (track != null) {
        tracks.add(track);
      }
    }
    return (playlist, tracks);
  }

  /// Save a playlist
  Future<void> savePlaylist(Playlist playlist) async {
    final isar = await _getIsar();
    playlist.updatedAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.playlists.put(playlist);
    });
  }

  /// Delete a playlist
  Future<void> deletePlaylist(int id) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.playlists.delete(id);
    });
  }

  /// Clear all playlists
  Future<void> clearAllPlaylists() async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.playlists.clear();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // CUSTOM MOOD METHODS
  // ═══════════════════════════════════════════════════════════════

  /// Get all custom moods
  Future<List<CustomMood>> getAllCustomMoods() async {
    final isar = await _getIsar();
    return await isar.customMoods.where().findAll();
  }

  /// Get a custom mood by ID
  Future<CustomMood?> getCustomMoodById(int id) async {
    final isar = await _getIsar();
    return await isar.customMoods.get(id);
  }

  /// Create a new custom mood
  Future<CustomMood> createCustomMood({
    required String name,
    String icon = '🎵',
    int colorValue = 0xFF7C6CFF,
  }) async {
    final isar = await _getIsar();
    final mood = CustomMood()
      ..name = name
      ..icon = icon
      ..colorValue = colorValue
      ..createdAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.customMoods.put(mood);
    });
    return mood;
  }

  /// Save/update a custom mood (name, icon, color, membership...)
  Future<void> saveCustomMood(CustomMood mood) async {
    final isar = await _getIsar();
    mood.updatedAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.customMoods.put(mood);
    });
  }

  /// Delete a custom mood
  Future<void> deleteCustomMood(int id) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.customMoods.delete(id);
    });
  }

  /// Add a track to a custom mood with a match percentage (0-100). If the
  /// track is already in the mood, just updates its percentage.
  Future<void> addTrackToCustomMood(int moodId, int trackId, {double percentage = 100}) async {
    final isar = await _getIsar();
    final mood = await isar.customMoods.get(moodId);
    if (mood == null) return;

    final existingIndex = mood.trackIds.indexOf(trackId);
    if (existingIndex != -1) {
      mood.trackPercentages[existingIndex] = percentage.clamp(0, 100);
    } else {
      mood.trackIds = [...mood.trackIds, trackId];
      mood.trackPercentages = [...mood.trackPercentages, percentage.clamp(0, 100)];
    }
    await saveCustomMood(mood);
  }

  /// Remove a track from a custom mood
  Future<void> removeTrackFromCustomMood(int moodId, int trackId) async {
    final isar = await _getIsar();
    final mood = await isar.customMoods.get(moodId);
    if (mood == null) return;

    final index = mood.trackIds.indexOf(trackId);
    if (index == -1) return;

    final newTrackIds = List<int>.from(mood.trackIds)..removeAt(index);
    final newPercentages = List<double>.from(mood.trackPercentages)..removeAt(index);
    mood.trackIds = newTrackIds;
    mood.trackPercentages = newPercentages;
    await saveCustomMood(mood);
  }

  /// Update a track's match percentage within a custom mood
  Future<void> setTrackPercentageInMood(int moodId, int trackId, double percentage) async {
    final isar = await _getIsar();
    final mood = await isar.customMoods.get(moodId);
    if (mood == null) return;

    final index = mood.trackIds.indexOf(trackId);
    if (index == -1) return;

    final newPercentages = List<double>.from(mood.trackPercentages);
    newPercentages[index] = percentage.clamp(0, 100);
    mood.trackPercentages = newPercentages;
    await saveCustomMood(mood);
  }

  /// Get all tracks in a custom mood, paired with their percentage.
  Future<List<(Track, double)>> getTracksInCustomMood(int moodId) async {
    final isar = await _getIsar();
    final mood = await isar.customMoods.get(moodId);
    if (mood == null) return [];

    final result = <(Track, double)>[];
    for (var i = 0; i < mood.trackIds.length; i++) {
      final track = await isar.tracks.get(mood.trackIds[i]);
      if (track != null) {
        final pct = i < mood.trackPercentages.length ? mood.trackPercentages[i] : 100.0;
        result.add((track, pct));
      }
    }
    return result;
  }

  /// Which custom moods a given track currently belongs to.
  Future<List<CustomMood>> getCustomMoodsForTrack(int trackId) async {
    final isar = await _getIsar();
    final allMoods = await isar.customMoods.where().findAll();
    return allMoods.where((m) => m.trackIds.contains(trackId)).toList();
  }

  // ═══════════════════════════════════════════════════════════════
  // ÉCOUTES RÉELLES (≥ 80 % de la durée) + RECHERCHES RÉCENTES
  // ═══════════════════════════════════════════════════════════════
  //
  // Stockés dans de simples fichiers JSON à côté de la base Isar, comme
  // les favoris : ce sont des données purement dérivées/annexes, et les
  // garder hors du schéma Isar évite une migration de base (et évite que
  // la réinitialisation d'urgence d'Isar les emporte avec elle).

  static Map<int, int>? _playCountsCache;
  static List<String>? _recentSearchesCache;

  /// Nombre max de recherches récentes conservées.
  static const int _maxRecentSearches = 15;

  Future<File> _playCountsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/play_counts.json');
  }

  Future<File> _recentSearchesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/recent_searches.json');
  }

  Future<Map<int, int>> _loadPlayCounts() async {
    if (_playCountsCache != null) return _playCountsCache!;
    try {
      final file = await _playCountsFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _playCountsCache = {
          for (final entry in decoded.entries)
            int.parse(entry.key): (entry.value as num).toInt(),
        };
      } else {
        _playCountsCache = <int, int>{};
      }
    } catch (_) {
      _playCountsCache = <int, int>{};
    }
    return _playCountsCache!;
  }

  /// Compteurs d'écoute « réelles » par id de morceau.
  Future<Map<int, int>> getPlayCounts() async {
    return Map<int, int>.from(await _loadPlayCounts());
  }

  /// Incrémente le compteur d'un morceau. À n'appeler que lorsque le
  /// morceau a réellement été écouté à plus de 80 % de sa durée — un
  /// simple « lancé puis zappé » ne doit pas compter.
  Future<Map<int, int>> incrementPlayCount(int trackId) async {
    final counts = await _loadPlayCounts();
    counts[trackId] = (counts[trackId] ?? 0) + 1;
    _playCountsCache = counts;
    try {
      final file = await _playCountsFile();
      await file.writeAsString(
        jsonEncode({for (final e in counts.entries) e.key.toString(): e.value}),
      );
    } catch (_) {
      // Non critique : le compteur reste au moins correct en mémoire
      // pour la session en cours.
    }
    return Map<int, int>.from(counts);
  }

  Future<List<String>> _loadRecentSearches() async {
    if (_recentSearchesCache != null) return _recentSearchesCache!;
    try {
      final file = await _recentSearchesFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        _recentSearchesCache = decoded.map((e) => e as String).toList();
      } else {
        _recentSearchesCache = <String>[];
      }
    } catch (_) {
      _recentSearchesCache = <String>[];
    }
    return _recentSearchesCache!;
  }

  Future<void> _saveRecentSearches(List<String> searches) async {
    _recentSearchesCache = searches;
    try {
      final file = await _recentSearchesFile();
      await file.writeAsString(jsonEncode(searches));
    } catch (_) {}
  }

  Future<List<String>> getRecentSearches() async {
    return List<String>.from(await _loadRecentSearches());
  }

  /// Ajoute une recherche en tête de liste, sans doublon (comparaison
  /// insensible à la casse) et en bornant la taille de l'historique.
  Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final searches = await _loadRecentSearches();
    searches.removeWhere((s) => s.toLowerCase() == trimmed.toLowerCase());
    searches.insert(0, trimmed);
    if (searches.length > _maxRecentSearches) {
      searches.removeRange(_maxRecentSearches, searches.length);
    }
    await _saveRecentSearches(searches);
  }

  Future<void> removeRecentSearch(String query) async {
    final searches = await _loadRecentSearches();
    searches.removeWhere((s) => s.toLowerCase() == query.toLowerCase());
    await _saveRecentSearches(searches);
  }

  Future<void> clearRecentSearches() async {
    await _saveRecentSearches(<String>[]);
  }

  Future<Isar> _getIsar() async {
    if (_isar == null) {
      await initialize();
    }
    return _isar!;
  }

  /// Close Isar instance
  static Future<void> close() async {
    if (_isar != null) {
      await _isar!.close();
      _isar = null;
    }
  }
}