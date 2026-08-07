import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import '../models/playlist.dart';

class StorageService {
  static Isar? _isar;
  
  /// Initialize Isar database
  static Future<void> initialize() async {
    if (_isar != null) return;
    
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [TrackSchema, PlaylistSchema],
      directory: dir.path,
    );
  }

  /// Get all tracks
  Future<List<Track>> getAllTracks() async {
    final isar = await _getIsar();
    return await isar.tracks.where().findAll();
  }

  /// Get tracks by mood
  Future<List<Track>> getTracksByMood(MoodType mood) async {
    final isar = await _getIsar();
    return await isar.tracks
        .where()
        .filter()
        .moodIndexEqualTo(mood.index)
        .findAll();
  }

  /// Get unclassified tracks (mood is null)
  Future<List<Track>> getUnclassifiedTracks() async {
    final isar = await _getIsar();
    return await isar.tracks
        .where()
        .filter()
        .moodIndexIsNull()
        .findAll();
  }

  /// Search tracks by title or artist
  Future<List<Track>> searchTracks(String query) async {
    final isar = await _getIsar();
    final lowerQuery = query.toLowerCase();
    
    return await isar.tracks
        .where()
        .filter()
        .titleContains(lowerQuery)
        .or()
        .artistContains(lowerQuery)
        .findAll();
  }

  /// Get a single track by ID
  Future<Track?> getTrackById(int id) async {
    final isar = await _getIsar();
    return await isar.tracks.get(id);
  }

  /// Insert or update a track
  Future<void> saveTrack(Track track) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await isar.tracks.put(track);
    });
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