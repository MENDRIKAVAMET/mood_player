import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
    final local = await _readLocalLrc(filePath, title: title, artist: artist);
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

  /// L'app a-t-elle le droit de lire des fichiers non-média (donc les
  /// `.lrc`) sur le stockage partagé ?
  ///
  /// Sur Android 11+, la permission audio ne suffit pas : un `.lrc` n'est
  /// pas un fichier média aux yeux du système, et `File.readAsString()`
  /// échoue même sur un fichier posé juste à côté du MP3.
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    return await Permission.manageExternalStorage.isGranted;
  }

  /// Ouvre l'écran système « Accès à tous les fichiers ». Renvoie true si
  /// l'utilisateur a accordé la permission.
  static Future<bool> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  /// Dossiers où chercher des `.lrc` en plus du dossier du morceau.
  ///
  /// Beaucoup d'applis (et de sites de téléchargement) rangent les
  /// paroles à part au lieu de les poser à côté du fichier audio. Chercher
  /// uniquement `<même dossier>/<même nom>.lrc` rate tous ces cas — c'est
  /// exactement pourquoi rien ne se trouvait.
  static const _extraLyricsDirs = [
    '/storage/emulated/0/Lyrics',
    '/storage/emulated/0/Music/Lyrics',
    '/storage/emulated/0/Download/Lyrics',
    '/storage/emulated/0/Android/data/com.example.mood_player/files/Lyrics',
  ];

  /// Normalise un nom pour comparer « Bob Marley - War (Live).lrc » et
  /// « bob_marley war live.mp3 » : minuscules, accents et ponctuation
  /// retirés, espaces écrasés.
  static String _normalize(String input) {
    final lower = input.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buffer.write(ch);
      } else if ('àâäáãåÀÂÄ'.contains(ch)) {
        buffer.write('a');
      } else if ('éèêëÉÈÊË'.contains(ch)) {
        buffer.write('e');
      } else if ('îïíìÎÏ'.contains(ch)) {
        buffer.write('i');
      } else if ('ôöóòõÔÖ'.contains(ch)) {
        buffer.write('o');
      } else if ('ûüùúÛÜ'.contains(ch)) {
        buffer.write('u');
      }
    }
    return buffer.toString();
  }

  /// Cherche un `.lrc` correspondant au morceau.
  ///
  /// Trois passes, de la plus sûre à la plus permissive :
  /// 1. même dossier, même nom de base (le cas standard) ;
  /// 2. n'importe quel `.lrc` du même dossier dont le nom normalisé
  ///    correspond au fichier, au titre, ou à « artiste titre » ;
  /// 3. les dossiers de paroles dédiés listés ci-dessus.
  Future<LyricsResult?> _readLocalLrc(
    String? filePath, {
    String? title,
    String? artist,
  }) async {
    if (filePath == null || filePath.isEmpty) return null;

    try {
      final lastDot = filePath.lastIndexOf('.');
      final base = lastDot > 0 ? filePath.substring(0, lastDot) : filePath;

      // 1. Le cas évident.
      for (final candidate in ['$base.lrc', '$base.LRC']) {
        final parsed = await _tryParseLrc(candidate);
        if (parsed != null) return parsed;
      }

      // Noms acceptables, normalisés.
      final lastSlash = filePath.lastIndexOf('/');
      final dirPath = lastSlash > 0 ? filePath.substring(0, lastSlash) : null;
      final fileStem = base.substring(base.lastIndexOf('/') + 1);

      final targets = <String>{
        _normalize(fileStem),
        if (title != null && title.isNotEmpty) _normalize(title),
        if (title != null && artist != null) _normalize('$artist $title'),
        if (title != null && artist != null) _normalize('$title $artist'),
      }..removeWhere((t) => t.length < 3);

      // 2. Le dossier du morceau.
      if (dirPath != null) {
        final found = await _scanDirForLrc(dirPath, targets);
        if (found != null) return found;
      }

      // 3. Les dossiers de paroles dédiés.
      for (final dir in _extraLyricsDirs) {
        final found = await _scanDirForLrc(dir, targets);
        if (found != null) return found;
      }
    } catch (_) {
      // Dossier illisible, permission refusée : on bascule sur la
      // recherche en ligne plutôt que de planter l'écran.
    }
    return null;
  }

  /// Parcourt un dossier (sans récursion) à la recherche d'un `.lrc` dont
  /// le nom normalisé correspond à l'une des [targets].
  Future<LyricsResult?> _scanDirForLrc(String dirPath, Set<String> targets) async {
    if (targets.isEmpty) return null;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return null;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last;
        if (!name.toLowerCase().endsWith('.lrc')) continue;

        final stem = _normalize(name.substring(0, name.length - 4));
        if (stem.isEmpty) continue;

        final matches = targets.any(
          (t) => stem == t || stem.contains(t) || t.contains(stem),
        );
        if (!matches) continue;

        final parsed = await _tryParseLrc(entity.path);
        if (parsed != null) return parsed;
      }
    } catch (_) {
      // Un dossier inaccessible ne doit pas interrompre les suivants.
    }
    return null;
  }

  /// Lit et parse un `.lrc` s'il existe et contient des lignes horodatées.
  Future<LyricsResult?> _tryParseLrc(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final lines = parseLrc(content);
      if (lines.isEmpty) return null;
      return LyricsResult(
        synced: lines,
        localPath: path,
        offset: readLrcOffset(content),
      );
    } catch (_) {
      return null;
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
