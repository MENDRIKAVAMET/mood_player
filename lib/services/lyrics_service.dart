import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/lyric_line.dart';

/// Result of a lyrics lookup: synced (line-by-line timestamped) lyrics
/// when available, otherwise plain unsynced text, otherwise neither if the
/// track just isn't in the database.
class LyricsResult {
  final List<LyricLine>? synced;
  final String? plain;
  final bool instrumental;

  const LyricsResult({this.synced, this.plain, this.instrumental = false});

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
  }) async {
    try {
      final exact = await _getExact(title: title, artist: artist, duration: duration);
      if (exact != null) return exact;

      return await _search(title: title, artist: artist) ?? const LyricsResult();
    } catch (_) {
      // Network failure, malformed response, etc. - just show "no lyrics"
      // rather than surfacing an error over what's otherwise a working
      // playback session.
      return const LyricsResult();
    }
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

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
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
}
