import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../models/user_profile.dart';
import 'storage_service.dart';

/// Fichier de transfert illisible ou qui ne vient pas de Mood Player.
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);

  @override
  String toString() => message;
}

/// Un morceau tel que décrit dans le fichier de transfert.
///
/// Les identifiants Isar d'un téléphone n'ont aucun sens sur un autre :
/// [ref] n'est qu'un numéro de liaison interne au fichier (l'id d'origine),
/// et c'est le couple artiste + titre (+ durée) qui sert à retrouver le même
/// morceau sur l'appareil qui importe.
class BackupTrack {
  final int ref;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;

  /// Nom de [MoodType] (`chill`...), null si le morceau n'était pas classé.
  final String? mood;
  final double? moodConfidence;
  final DateTime? lastClassified;

  const BackupTrack({
    required this.ref,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.mood,
    this.moodConfidence,
    this.lastClassified,
  });

  MoodType? get moodType {
    final m = mood;
    if (m == null) return null;
    for (final t in MoodType.values) {
      if (t.name == m) return t;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'ref': ref,
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
        if (durationMs != null) 'durationMs': durationMs,
        if (mood != null) 'mood': mood,
        if (moodConfidence != null) 'moodConfidence': moodConfidence,
        if (lastClassified != null)
          'lastClassified': lastClassified!.toUtc().toIso8601String(),
      };

  factory BackupTrack.fromJson(Map<String, dynamic> j) => BackupTrack(
        ref: (j['ref'] as num).toInt(),
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String?,
        durationMs: (j['durationMs'] as num?)?.toInt(),
        mood: j['mood'] as String?,
        moodConfidence: (j['moodConfidence'] as num?)?.toDouble(),
        lastClassified: j['lastClassified'] == null
            ? null
            : DateTime.tryParse(j['lastClassified'] as String)?.toLocal(),
      );
}

/// Une ambiance perso du fichier : ses morceaux sont désignés par [BackupTrack.ref].
class BackupCustomMood {
  final String name;
  final String icon;
  final int colorValue;

  /// ref du morceau -> pourcentage (0-100).
  final Map<int, double> entries;

  const BackupCustomMood({
    required this.name,
    required this.icon,
    required this.colorValue,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'icon': icon,
        'colorValue': colorValue,
        'tracks': [
          for (final e in entries.entries) {'ref': e.key, 'pct': e.value},
        ],
      };

  factory BackupCustomMood.fromJson(Map<String, dynamic> j) =>
      BackupCustomMood(
        name: j['name'] as String? ?? '',
        icon: j['icon'] as String? ?? 'music',
        colorValue: (j['colorValue'] as num?)?.toInt() ?? 0xFF7C6CFF,
        entries: {
          for (final t in (j['tracks'] as List<dynamic>? ?? const []))
            ((t as Map)['ref'] as num).toInt():
                ((t['pct'] as num?)?.toDouble() ?? 100.0),
        },
      );
}

/// Contenu complet d'un fichier de transfert.
class BackupData {
  final DateTime exportedAt;
  final List<BackupTrack> tracks;
  final Set<int> likedRefs;
  final Map<int, int> playCounts;
  final List<BackupCustomMood> customMoods;
  final List<String> favoriteArtists;
  final Map<String, List<String>> periodMoods;
  final bool? smartQueueEnabled;

  const BackupData({
    required this.exportedAt,
    required this.tracks,
    this.likedRefs = const {},
    this.playCounts = const {},
    this.customMoods = const [],
    this.favoriteArtists = const [],
    this.periodMoods = const {},
    this.smartQueueEnabled,
  });

  /// Nombre de morceaux qui portent une classification utilisable.
  int get classifiedCount =>
      tracks.where((t) => t.moodType != null && t.moodType != MoodType.unknown).length;

  bool get hasPersonalData =>
      likedRefs.isNotEmpty ||
      playCounts.isNotEmpty ||
      customMoods.isNotEmpty ||
      favoriteArtists.isNotEmpty ||
      periodMoods.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'app': BackupService.appId,
        'version': BackupService.formatVersion,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'liked': likedRefs.toList(),
        'playCounts': {
          for (final e in playCounts.entries) e.key.toString(): e.value,
        },
        'customMoods': customMoods.map((m) => m.toJson()).toList(),
        'profile': {
          'favoriteArtists': favoriteArtists,
          'periodMoods': periodMoods,
          if (smartQueueEnabled != null) 'smartQueueEnabled': smartQueueEnabled,
        },
      };

  factory BackupData.fromJson(Map<String, dynamic> j) {
    final profile = (j['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BackupData(
      exportedAt:
          DateTime.tryParse(j['exportedAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      tracks: [
        for (final t in (j['tracks'] as List<dynamic>? ?? const []))
          BackupTrack.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
      likedRefs: {
        for (final r in (j['liked'] as List<dynamic>? ?? const []))
          (r as num).toInt(),
      },
      playCounts: {
        for (final e
            in ((j['playCounts'] as Map?) ?? const {}).entries)
          int.parse(e.key.toString()): (e.value as num).toInt(),
      },
      customMoods: [
        for (final m in (j['customMoods'] as List<dynamic>? ?? const []))
          BackupCustomMood.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      favoriteArtists: [
        for (final a in (profile['favoriteArtists'] as List<dynamic>? ?? const []))
          a.toString(),
      ],
      periodMoods: {
        for (final e in ((profile['periodMoods'] as Map?) ?? const {}).entries)
          e.key.toString():
              (e.value as List<dynamic>).map((x) => x.toString()).toList(),
      },
      smartQueueEnabled: profile['smartQueueEnabled'] as bool?,
    );
  }
}

/// Bilan d'un import, affiché à l'utilisateur.
class BackupImportResult {
  /// Morceaux décrits dans le fichier.
  final int totalInFile;

  /// Morceaux du fichier retrouvés sur cet appareil.
  final int matched;

  /// Classifications écrites sur cet appareil.
  final int classificationsApplied;

  /// Classifications du fichier ignorées car le morceau était déjà classé
  /// ici (et l'écrasement n'était pas demandé).
  final int classificationsKept;

  final int likedAdded;
  final int customMoodTracksAdded;

  const BackupImportResult({
    required this.totalInFile,
    required this.matched,
    required this.classificationsApplied,
    required this.classificationsKept,
    required this.likedAdded,
    required this.customMoodTracksAdded,
  });

  int get unmatched => totalInFile - matched;
}

/// Export / import des données de l'app dans un fichier JSON, pour changer
/// de téléphone ou récupérer les classifications d'une autre personne sans
/// refaire d'appels à l'IA (donc hors ligne).
class BackupService {
  static const String appId = 'mood_player';
  static const int formatVersion = 1;

  /// Écart de durée au-delà duquel deux morceaux de même titre/artiste sont
  /// considérés comme deux versions différentes (live, remix...).
  static const int durationToleranceMs = 5000;

  final StorageService _storage;

  BackupService(this._storage);

  // ───────────────────────── Appariement ─────────────────────────

  static const String _accentsFrom = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœ';
  static const String _accentsTo = 'aaaaaaceeeeiiiinooooouuuuyyo';

  static String _normalize(String s) {
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final i = _accentsFrom.indexOf(ch);
      buf.write(i >= 0 ? _accentsTo[i] : ch);
    }
    // On ne garde que lettres et chiffres (tous alphabets) : "Artist - Song"
    // et "artist–song!" désignent le même morceau.
    return buf.toString().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  }

  /// Clé de comparaison artiste + titre, insensible à la casse, aux accents
  /// et à la ponctuation.
  static String trackKey(String title, String artist) =>
      '${_normalize(artist)}|${_normalize(title)}';

  /// Associe chaque morceau du fichier (par [BackupTrack.ref]) au morceau
  /// local correspondant. Un morceau local ne sert qu'une fois.
  static Map<int, Track> matchTracks(
    List<BackupTrack> backup,
    List<Track> local,
  ) {
    final byKey = <String, List<Track>>{};
    for (final t in local) {
      byKey.putIfAbsent(trackKey(t.title, t.artist), () => []).add(t);
    }

    final used = <int>{};
    final result = <int, Track>{};

    for (final bt in backup) {
      final candidates = byKey[trackKey(bt.title, bt.artist)];
      if (candidates == null) continue;

      Track? best;
      var bestDiff = 1 << 30;
      for (final c in candidates) {
        if (used.contains(c.id)) continue;
        final a = bt.durationMs;
        final b = c.duration;
        var diff = 0;
        if (a != null && b != null && a > 0 && b > 0) {
          diff = (a - b).abs();
          if (diff > durationToleranceMs) continue;
        }
        if (diff < bestDiff) {
          best = c;
          bestDiff = diff;
        }
      }
      if (best != null) {
        used.add(best.id);
        result[bt.ref] = best;
      }
    }
    return result;
  }

  // ───────────────────────── Export ─────────────────────────

  /// Construit le contenu à exporter à partir de l'état actuel.
  Future<BackupData> buildBackup({required UserProfile profile}) async {
    final tracks = await _storage.getAllTracks();
    final liked = await _storage.getLikedTrackIds();
    final counts = await _storage.getPlayCounts();
    final moods = await _storage.getAllCustomMoods();

    final inCustomMood = <int>{for (final m in moods) ...m.trackIds};

    final exported = <BackupTrack>[];
    final exportedIds = <int>{};
    for (final t in tracks) {
      final mood = t.mood;
      final classified = mood != null && mood != MoodType.unknown;
      final relevant = classified ||
          liked.contains(t.id) ||
          (counts[t.id] ?? 0) > 0 ||
          inCustomMood.contains(t.id);
      if (!relevant) continue;
      exportedIds.add(t.id);
      exported.add(BackupTrack(
        ref: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        durationMs: t.duration,
        mood: classified ? mood.name : null,
        moodConfidence: classified ? t.moodConfidence : null,
        lastClassified: classified ? t.lastClassified : null,
      ));
    }

    return BackupData(
      exportedAt: DateTime.now(),
      tracks: exported,
      likedRefs: liked.where(exportedIds.contains).toSet(),
      playCounts: {
        for (final e in counts.entries)
          if (exportedIds.contains(e.key) && e.value > 0) e.key: e.value,
      },
      customMoods: [
        for (final m in moods)
          BackupCustomMood(
            name: m.name,
            icon: m.icon,
            colorValue: m.colorValue,
            entries: {
              for (var i = 0; i < m.trackIds.length; i++)
                if (exportedIds.contains(m.trackIds[i]))
                  m.trackIds[i]: i < m.trackPercentages.length
                      ? m.trackPercentages[i]
                      : 100.0,
            },
          ),
      ],
      favoriteArtists: profile.favoriteArtists,
      periodMoods: profile.periodMoods,
      smartQueueEnabled: profile.smartQueueEnabled,
    );
  }

  /// Écrit la sauvegarde dans un fichier temporaire prêt à être partagé.
  Future<File> exportToFile({required UserProfile profile}) async {
    final data = await buildBackup(profile: profile);
    final dir = await getTemporaryDirectory();
    final d = data.exportedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
    final file = File('${dir.path}/mood_player_transfert_$stamp.json');
    await file.writeAsString(jsonEncode(data.toJson()));
    return file;
  }

  // ───────────────────────── Import ─────────────────────────

  /// Lit et valide un fichier de transfert. Lève [BackupFormatException]
  /// avec un message affichable s'il n'est pas utilisable.
  static BackupData parse(String content) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const BackupFormatException(
          'Ce fichier n\'est pas un fichier de transfert Mood Player.');
    }
    if (decoded is! Map || decoded['app'] != appId) {
      throw const BackupFormatException(
          'Ce fichier n\'est pas un fichier de transfert Mood Player.');
    }
    final version = decoded['version'];
    if (version is! int || version > formatVersion) {
      throw const BackupFormatException(
          'Ce fichier vient d\'une version plus récente de Mood Player. '
          'Mettez l\'application à jour pour l\'importer.');
    }
    try {
      return BackupData.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      throw const BackupFormatException(
          'Le fichier de transfert est abîmé et ne peut pas être lu.');
    }
  }

  Future<BackupData> readFile(String path) async {
    final String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      throw const BackupFormatException('Impossible de lire ce fichier.');
    }
    return parse(content);
  }

  /// Applique [data] sur cet appareil.
  ///
  /// - Les classifications sont toujours importées pour les morceaux
  ///   retrouvés ; un morceau déjà classé ici n'est remplacé que si
  ///   [overwriteClassifications] est vrai.
  /// - Favoris, ambiances perso et compteurs d'écoute (données
  ///   « personnelles ») ne sont importés que si [includePersonalData]
  ///   est vrai - on ne veut pas forcément les favoris d'une autre personne.
  ///
  /// Le profil (artistes préférés...) n'est pas traité ici : l'appelant
  /// l'applique via le ProfileNotifier pour que l'interface se mette à jour.
  Future<BackupImportResult> apply(
    BackupData data, {
    required bool overwriteClassifications,
    required bool includePersonalData,
  }) async {
    final local = await _storage.getAllTracks();
    final matched = matchTracks(data.tracks, local);

    final now = DateTime.now();
    final toSave = <Track>[];
    var kept = 0;

    for (final bt in data.tracks) {
      final track = matched[bt.ref];
      final mood = bt.moodType;
      if (track == null || mood == null || mood == MoodType.unknown) continue;

      final alreadyClassified =
          track.mood != null && track.mood != MoodType.unknown;
      if (alreadyClassified && !overwriteClassifications) {
        kept++;
        continue;
      }
      track
        ..mood = mood
        ..moodConfidence = bt.moodConfidence?.clamp(0.0, 1.0).toDouble()
        ..lastClassified = bt.lastClassified ?? now
        ..updatedAt = now;
      toSave.add(track);
    }
    if (toSave.isNotEmpty) await _storage.saveTracks(toSave);

    var likedAdded = 0;
    var customAdded = 0;

    if (includePersonalData) {
      final likedLocalIds = <int>{
        for (final ref in data.likedRefs)
          if (matched[ref] != null) matched[ref]!.id,
      };
      if (likedLocalIds.isNotEmpty) {
        final before = await _storage.getLikedTrackIds();
        likedAdded = likedLocalIds.difference(before).length;
        await _storage.addLikedTrackIds(likedLocalIds);
      }

      final counts = <int, int>{
        for (final e in data.playCounts.entries)
          if (matched[e.key] != null) matched[e.key]!.id: e.value,
      };
      if (counts.isNotEmpty) await _storage.mergePlayCounts(counts);

      for (final mood in data.customMoods) {
        if (mood.name.trim().isEmpty) continue;
        final entries = <int, double>{
          for (final e in mood.entries.entries)
            if (matched[e.key] != null) matched[e.key]!.id: e.value,
        };
        customAdded += await _storage.importCustomMood(
          name: mood.name,
          icon: mood.icon,
          colorValue: mood.colorValue,
          entries: entries,
        );
      }
    }

    return BackupImportResult(
      totalInFile: data.tracks.length,
      matched: matched.length,
      classificationsApplied: toSave.length,
      classificationsKept: kept,
      likedAdded: likedAdded,
      customMoodTracksAdded: customAdded,
    );
  }
}
