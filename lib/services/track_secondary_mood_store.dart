import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

/// Ambiance secondaire de chaque morceau (ex. « Chill » + « Nostalgique »),
/// gardée par chemin de fichier dans un JSON à part, comme les genres ou les
/// favoris : le schéma Isar ne change pas, donc aucune migration.
///
/// Stockée par NOM d'ambiance (`MoodType.name`) et non par index, pour rester
/// valide même si l'enum évolue.
class TrackSecondaryMoods {
  static Map<String, MoodType>? _cache;

  /// Surcharge possible pour les tests (évite path_provider).
  static Future<File> Function()? fileOverride;

  static Future<File> _file() async {
    if (fileOverride != null) return fileOverride!();
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/track_secondary_moods.json');
  }

  /// Vide le cache mémoire (tests, restauration de sauvegarde).
  static void resetCache() => _cache = null;

  static Future<Map<String, MoodType>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final out = <String, MoodType>{};
          decoded.forEach((key, value) {
            if (key is! String || value is! String) return;
            for (final m in MoodType.values) {
              if (m.name == value && m != MoodType.unknown) {
                out[key] = m;
                break;
              }
            }
          });
          return _cache = out;
        }
      }
    } catch (_) {
      // Absent ou corrompu : on repart de zéro, ce n'est qu'un bonus.
    }
    return _cache = <String, MoodType>{};
  }

  static Future<void> _persist(Map<String, MoodType> map) async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({for (final e in map.entries) e.key: e.value.name}),
      );
    } catch (_) {
      // Le cache mémoire garde la valeur pour la session.
    }
  }

  /// Définit (ou, avec null / « inconnu », retire) l'ambiance secondaire du
  /// fichier [path].
  static Future<void> set(String? path, MoodType? mood) async {
    if (path == null) return;
    final map = await load();
    final effective = (mood == null || mood == MoodType.unknown) ? null : mood;
    if (map[path] == effective) return;
    if (effective == null) {
      map.remove(path);
    } else {
      map[path] = effective;
    }
    await _persist(map);
  }

  /// Ajoute plusieurs entrées d'un coup (classification en lot) ; n'écrit
  /// que si quelque chose a changé.
  static Future<void> merge(Map<String, MoodType> incoming) async {
    if (incoming.isEmpty) return;
    final map = await load();
    var changed = false;
    incoming.forEach((path, mood) {
      if (mood == MoodType.unknown) return;
      if (map[path] != mood) {
        map[path] = mood;
        changed = true;
      }
    });
    if (changed) await _persist(map);
  }

  /// Le fichier a été renommé / déplacé : l'ambiance suit.
  static Future<void> move(String? oldPath, String? newPath) async {
    if (oldPath == null || newPath == null || oldPath == newPath) return;
    final map = await load();
    final mood = map.remove(oldPath);
    if (mood == null) return;
    map[newPath] = mood;
    await _persist(map);
  }

  static Future<void> remove(String? path) => set(path, null);

  static Future<void> clear() async {
    _cache = <String, MoodType>{};
    await _persist(_cache!);
  }

  /// Pose l'ambiance secondaire mémorisée sur chaque morceau de [tracks].
  static Future<void> applyTo(Iterable<Track> tracks) async {
    final map = await load();
    for (final t in tracks) {
      final p = t.filePath;
      t.secondaryMood = p == null ? null : map[p];
    }
  }
}
