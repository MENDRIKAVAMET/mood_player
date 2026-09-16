import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lyric_line.dart';

/// Result of a lyrics lookup: synced (line-by-line timestamped) lyrics
/// when available, otherwise plain unsynced text, otherwise neither if the
/// track just isn't in the database.
class LyricsResult {
  final List<LyricLine>? synced;
  final String? plain;
  final bool instrumental;

  /// Path of the local `.lrc` file these lyrics came from, when they were
  /// loaded from disk rather than fetched online. Used to write timing
  /// offsets back to the same file.
  final String? localPath;

  /// User-adjusted timing offset applied to [synced] timestamps. Positive
  /// means the lyrics are shown later, negative means earlier.
  final Duration offset;

  const LyricsResult({
    this.synced,
    this.plain,
    this.instrumental = false,
    this.localPath,
    this.offset = Duration.zero,
  });

  LyricsResult copyWith({Duration? offset}) => LyricsResult(
        synced: synced,
        plain: plain,
        instrumental: instrumental,
        localPath: localPath,
        offset: offset ?? this.offset,
      );

  bool get hasSynced => synced != null && synced!.isNotEmpty;
  bool get hasAny => hasSynced || (plain != null && plain!.isNotEmpty) || instrumental;
}

/// Looks up song lyrics from lrclib.net - a free, keyless, community-run
/// lyrics database built specifically for synced (LRC) lyrics, which is
/// exactly what a karaoke-style line highlight needs. No API key, no
/// rate-limit hassle for the volume a single music player generates.
class LyricsService {
  static const _baseUrl = 'https://lrclib.net/api';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  /// Best-effort lookup: tries an exact match first (title + artist +
  /// duration, which lrclib uses to disambiguate different recordings of
  /// the same song), then falls back to a fuzzy search if that 404s.
  /// Returns an empty [LyricsResult] (never throws) if nothing is found or
  /// the network call fails - lyrics are a nice-to-have, never something
  /// that should interrupt playback.
  Future<LyricsResult> fetch({
    required String title,
    required String artist,
    Duration? duration,
    String? filePath,
  }) async {
    final trackKey = '$artist - $title';

    // A .lrc sitting next to the audio file is the user's own copy - it
    // wins over anything online, and it's also the file we write timing
    // offsets back to.
    final local = await _readLocalLrc(filePath);
    if (local != null) {
      // A stored offset only applies when the .lrc itself carries none
      // (i.e. we couldn't write to the file and fell back to our store).
      if (local.offset == Duration.zero) {
        final stored = await loadStoredOffset(trackKey);
        if (stored != null) return local.copyWith(offset: stored);
      }
      return local;
    }

    final stored = await loadStoredOffset(trackKey) ?? Duration.zero;

    try {
      final exact = await _getExact(title: title, artist: artist, duration: duration);
      if (exact != null) return exact.copyWith(offset: stored);

      final searched = await _search(title: title, artist: artist);
      return searched?.copyWith(offset: stored) ?? const LyricsResult();
    } catch (_) {
      // Network failure, malformed response, etc. - just show "no lyrics"
      // rather than surfacing an error over what's otherwise a working
      // playback session.
      return const LyricsResult();
    }
  }

  /// Looks for a `.lrc` file alongside the track's audio file (same
  /// directory, same base name) and parses it if present.
  Future<LyricsResult?> _readLocalLrc(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return null;
    try {
      final lastDot = filePath.lastIndexOf('.');
      final base = lastDot > 0 ? filePath.substring(0, lastDot) : filePath;
      for (final candidate in ['$base.lrc', '$base.LRC']) {
        final file = File(candidate);
        if (await file.exists()) {
          final content = await file.readAsString();
          final lines = parseLrc(content);
          if (lines.isEmpty) continue;
          return LyricsResult(
            synced: lines,
            localPath: candidate,
            offset: readLrcOffset(content),
          );
        }
      }
    } catch (_) {
      // Unreadable/permission-denied file - fall through to the online
      // lookup rather than failing the whole screen.
    }
    return null;
  }

  Future<LyricsResult?> _getExact({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    try {
      final response = await _dio.get('$_baseUrl/get', queryParameters: {
        'track_name': title,
        'artist_name': artist,
        if (duration != null) 'duration': duration.inSeconds.toString(),
      });
      if (response.statusCode != 200 || response.data == null) return null;
      return _parseResponseMap(_asMap(response.data));
    } on DioException catch (e) {
      // 404 just means "no exact match" - fall through to search instead
      // of treating it as a hard failure.
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<LyricsResult?> _search({
    required String title,
    required String artist,
  }) async {
    final response = await _dio.get('$_baseUrl/search', queryParameters: {
      'track_name': title,
      'artist_name': artist,
    });
    if (response.statusCode != 200) return null;

    final decoded = response.data;
    if (decoded is! List || decoded.isEmpty) return null;

    // Take the best-ranked result lrclib returns (first item), preferring
    // one that actually has synced lyrics if any candidate does.
    final withSynced = decoded.firstWhere(
      (e) => e is Map && (e['syncedLyrics'] as String?)?.isNotEmpty == true,
      orElse: () => decoded.first,
    );

    return _parseResponseMap(_asMap(withSynced));
  }

  Map<String, dynamic> _asMap(dynamic data) {    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data as Map);
  }

  LyricsResult _parseResponseMap(Map<String, dynamic> map) {
    final instrumental = map['instrumental'] == true;
    final syncedRaw = map['syncedLyrics'] as String?;
    final plainRaw = map['plainLyrics'] as String?;

    final synced = (syncedRaw != null && syncedRaw.isNotEmpty)
        ? parseLrc(syncedRaw)
        : null;

    return LyricsResult(
      synced: synced,
      plain: plainRaw,
      instrumental: instrumental,
    );
  }

  /// Persists the user's manual timing adjustment.
  ///
  /// When the lyrics came from a local `.lrc`, the offset is written into
  /// that file's `[offset:]` tag so it also applies in any other player.
  /// For lyrics fetched online there's no file to write to, so the value
  /// is kept in the app's own store, keyed by track.
  Future<void> saveOffset({
    required String trackKey,
    required Duration offset,
    String? localPath,
  }) async {
    if (localPath != null) {
      try {
        final file = File(localPath);
        final content = await file.readAsString();
        await file.writeAsString(writeLrcOffset(content, offset));
        return;
      } catch (_) {
        // Read-only location (common for files under scoped storage) -
        // fall back to the app-local store below so the adjustment still
        // survives a restart.
      }
    }
    await _saveOffsetLocally(trackKey, offset);
  }

  /// Returns a previously saved offset for [trackKey], or null.
  Future<Duration?> loadStoredOffset(String trackKey) async {
    final offsets = await _loadOffsets();
    final ms = offsets[trackKey];
    return ms == null ? null : Duration(milliseconds: ms);
  }

  static Map<String, int>? _offsetCache;

  Future<File> _offsetsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/lyrics_offsets.json');
  }

  Future<Map<String, int>> _loadOffsets() async {
    if (_offsetCache != null) return _offsetCache!;
    try {
      final file = await _offsetsFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _offsetCache = decoded.map((k, v) => MapEntry(k, v as int));
      } else {
        _offsetCache = <String, int>{};
      }
    } catch (_) {
      _offsetCache = <String, int>{};
    }
    return _offsetCache!;
  }

  Future<void> _saveOffsetLocally(String trackKey, Duration offset) async {
    final offsets = await _loadOffsets();
    offsets[trackKey] = offset.inMilliseconds;
    _offsetCache = offsets;
    try {
      final file = await _offsetsFile();
      await file.writeAsString(jsonEncode(offsets));
    } catch (_) {
      // Best effort - the in-memory cache still holds for this session.
    }
  }
}
