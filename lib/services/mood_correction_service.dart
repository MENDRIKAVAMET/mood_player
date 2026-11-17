import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

/// Une correction manuelle d'ambiance faite par l'utilisateur : « pour moi,
/// ce morceau est X ». Sert d'exemple dans le prompt Groq pour que la
/// classification reflète SA définition de chaque ambiance.
class MoodCorrection {
  final String title;
  final String artist;
  final String? album;

  /// Genre (tag du fichier) au moment de la correction. Sert à ne plus
  /// trancher localement un genre que l'utilisateur a déjà contredit.
  final String? genre;
  final MoodType mood;
  final DateTime at;

  const MoodCorrection({
    required this.title,
    required this.artist,
    this.album,
    this.genre,
    required this.mood,
    required this.at,
  });

  /// Clé stable entre deux scans (les ids Isar peuvent changer, pas le
  /// couple titre/artiste).
  String get key => keyFor(title, artist);

  static String keyFor(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
        if (genre != null) 'genre': genre,
        'mood': mood.name,
        'at': at.toIso8601String(),
      };

  static MoodCorrection? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    final artist = raw['artist'];
    final moodName = raw['mood'];
    if (title is! String || artist is! String || moodName is! String) {
      return null;
    }
    final mood = MoodType.values.where((m) => m.name == moodName).firstOrNull;
    if (mood == null || mood == MoodType.unknown) return null;
    return MoodCorrection(
      title: title,
      artist: artist,
      album: raw['album'] as String?,
      genre: raw['genre'] as String?,
      mood: mood,
      at: DateTime.tryParse(raw['at'] as String? ?? '') ?? DateTime(2000),
    );
  }
}

/// Mémorise les corrections manuelles (fichier JSON, comme les favoris,
/// donc sans migration du schéma Isar) et choisit lesquelles injecter dans
/// le prompt.
class MoodCorrectionService {
  /// Au-delà, les plus anciennes sont oubliées.
  static const int maxStored = 300;

  /// Nombre maximum d'exemples injectés par requête (tokens maîtrisés).
  static const int maxExamples = 30;

  /// Maximum d'exemples par ambiance, pour que le prompt reste équilibré.
  static const int maxPerMood = 5;

  /// Mots exacts utilisés dans le prompt de classification.
  static const Map<MoodType, String> promptLabels = {
    MoodType.energetic: 'énergique',
    MoodType.chill: 'chill',
    MoodType.melancholic: 'mélancolique',
    MoodType.festive: 'festif',
    MoodType.romantic: 'romantique',
    MoodType.concentration: 'concentration',
    MoodType.motivating: 'motivant',
    MoodType.sad: 'triste',
    MoodType.evangelical: 'évangélique',
    MoodType.angry: 'colère',
    MoodType.nostalgic: 'nostalgique',
    MoodType.dark: 'sombre',
    MoodType.sleep: 'sommeil',
    MoodType.funny: 'drôle',
    MoodType.roadtrip: 'voyage',
    MoodType.spiritual: 'spirituel',
    MoodType.classical: 'classique',
  };

  /// Surcharge possible pour les tests (évite path_provider).
  final Future<File> Function()? fileOverride;

  MoodCorrectionService({this.fileOverride});

  List<MoodCorrection>? _cache;

  Future<File> _file() async {
    if (fileOverride != null) return fileOverride!();
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/mood_corrections.json');
  }

  Future<List<MoodCorrection>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          return _cache =
              decoded.map(MoodCorrection.fromJson).whereType<MoodCorrection>().toList();
        }
      }
    } catch (_) {
      // Fichier absent ou corrompu : on repart de zéro, ce n'est qu'un bonus.
    }
    return _cache = <MoodCorrection>[];
  }

  Future<void> _save(List<MoodCorrection> list) async {
    _cache = list;
    final file = await _file();
    await file.writeAsString(jsonEncode(list.map((c) => c.toJson()).toList()));
  }

  Future<List<MoodCorrection>> getAll() async => List.of(await _load());

  /// Enregistre « pour l'utilisateur, [track] est [mood] ». Une nouvelle
  /// correction du même morceau remplace la précédente.
  Future<void> record(Track track, MoodType mood, {String? genre}) async {
    if (mood == MoodType.unknown) return;
    final list = await _load();
    final entry = MoodCorrection(
      title: track.title,
      artist: track.artist,
      album: track.album,
      genre: genre,
      mood: mood,
      at: DateTime.now(),
    );
    final next = [
      for (final c in list)
        if (c.key != entry.key) c,
      entry,
    ];
    if (next.length > maxStored) {
      next.sort((a, b) => a.at.compareTo(b.at));
      next.removeRange(0, next.length - maxStored);
    }
    await _save(next);
  }

  Future<void> clear() async => _save(<MoodCorrection>[]);

  /// Vrai si l'utilisateur a déjà reclassé un morceau de ce [genre] vers une
  /// autre ambiance que [mood] : la règle locale ne doit alors pas trancher
  /// à sa place, le morceau part chez Groq avec ses exemples.
  Future<bool> isContested(String genre, MoodType mood) async {
    final key = genre.trim().toLowerCase();
    final all = await _load();
    return all.any(
      (c) => c.genre != null && c.genre!.trim().toLowerCase() == key && c.mood != mood,
    );
  }

  /// Pour chaque genre (en minuscules) : les ambiances que l'utilisateur lui a
  /// données en corrigeant. Calculé une fois, il remplace un appel à
  /// [isContested] par morceau (des milliers d'appels × des centaines de
  /// corrections × un `toLowerCase` chacun).
  Future<Map<String, Set<MoodType>>> moodsByGenre() async {
    final out = <String, Set<MoodType>>{};
    for (final c in await _load()) {
      final g = c.genre;
      if (g == null) continue;
      (out[g.trim().toLowerCase()] ??= <MoodType>{}).add(c.mood);
    }
    return out;
  }

  /// Choisit les exemples les plus utiles pour [tracks] : d'abord ceux des
  /// mêmes artistes (le goût de l'utilisateur pour cet artiste), puis les
  /// plus récents, avec un plafond par ambiance.
  Future<List<MoodCorrection>> examplesFor(List<Track> tracks) async {
    final all = await _load();
    if (all.isEmpty) return const [];
    final artists = {for (final t in tracks) t.artist.trim().toLowerCase()};
    final own = {
      for (final t in tracks) MoodCorrection.keyFor(t.title, t.artist),
    };

    final sorted = all.where((c) => !own.contains(c.key)).toList()
      ..sort((a, b) {
        final sa = artists.contains(a.artist.trim().toLowerCase()) ? 0 : 1;
        final sb = artists.contains(b.artist.trim().toLowerCase()) ? 0 : 1;
        if (sa != sb) return sa - sb;
        return b.at.compareTo(a.at);
      });

    final perMood = <MoodType, int>{};
    final picked = <MoodCorrection>[];
    for (final c in sorted) {
      final n = perMood[c.mood] ?? 0;
      if (n >= maxPerMood) continue;
      perMood[c.mood] = n + 1;
      picked.add(c);
      if (picked.length >= maxExamples) break;
    }
    return picked;
  }

  /// Nettoie un texte venu des tags du fichier avant de l'insérer dans le
  /// prompt : une ligne, sans guillemets, longueur bornée (évite qu'un titre
  /// ne casse la mise en forme ou n'injecte des consignes).
  static String sanitize(String s, {int max = 80}) {
    final oneLine = s
        .replaceAll(RegExp(r'[\r\n\t"]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return oneLine.length > max ? '${oneLine.substring(0, max)}…' : oneLine;
  }

  /// Bloc de prompt listant les corrections, ou chaîne vide s'il n'y en a pas.
  static String buildPromptBlock(List<MoodCorrection> examples) {
    if (examples.isEmpty) return '';
    final b = StringBuffer()
      ..writeln(
        'PRÉFÉRENCES PERSONNELLES DE L\'UTILISATEUR : voici des morceaux '
        'qu\'il a lui-même reclassés. Sa définition de chaque ambiance '
        '(ce que LUI appelle « chill », « énergique », etc.) prime sur les '
        'descriptions ci-dessus. Déduis-en ses critères et applique-les aux '
        'morceaux proches (même artiste, même genre, même style) :',
      );
    for (final c in examples) {
      final album = (c.album != null && c.album!.isNotEmpty)
          ? ' | Album: ${sanitize(c.album!)}'
          : '';
      final genre = (c.genre != null && c.genre!.isNotEmpty)
          ? ' | Genre: ${sanitize(c.genre!, max: 40)}'
          : '';
      b.writeln(
        '- Titre: ${sanitize(c.title)} | Artiste: ${sanitize(c.artist)}$album$genre '
        '=> ${promptLabels[c.mood] ?? c.mood.name}',
      );
    }
    return b.toString();
  }
}
