import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Genre lu dans les tags (MediaStore) de chaque morceau, gardé par chemin
/// de fichier. Fichier JSON à part, comme les favoris ou les noms modifiés :
/// ça évite de toucher au schéma Isar (donc pas de migration).
class TrackGenres {
  static Map<String, String>? _cache;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/track_genres.json');
  }

  static Future<Map<String, String>> load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          return _cache = {
            for (final e in decoded.entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
          };
        }
      }
    } catch (_) {
      // Absent ou corrompu : on repart de zéro, le prochain scan le refait.
    }
    return _cache = <String, String>{};
  }

  /// Ajoute / met à jour [incoming] ; n'écrit sur le disque que si quelque
  /// chose a changé (cas le plus courant : rien).
  static Future<void> merge(Map<String, String> incoming) async {
    if (incoming.isEmpty) return;
    final map = await load();
    var changed = false;
    incoming.forEach((path, genre) {
      if (map[path] != genre) {
        map[path] = genre;
        changed = true;
      }
    });
    if (!changed) return;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(map));
    } catch (_) {
      // Le cache mémoire garde la valeur pour la session.
    }
  }
}
