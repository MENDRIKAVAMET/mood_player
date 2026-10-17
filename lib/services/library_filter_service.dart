import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Persiste le filtre « masquer les morceaux plus courts que X secondes » de
/// la bibliothèque, pour qu'il survive au redémarrage de l'app.
///
/// Petit fichier JSON local, comme le thème : une seule valeur lue au
/// démarrage et réécrite quand l'utilisateur la change.
class LibraryFilterService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/library_filter.json');
  }

  /// Durée minimale enregistrée, ou null (aucun filtre / lecture impossible).
  Future<int?> loadMinDurationSeconds() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      final value = json is Map ? json['minDurationSeconds'] : null;
      return value is int && value > 0 ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMinDurationSeconds(int? seconds) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'minDurationSeconds': seconds}));
    } catch (_) {
      // Le filtre reste valable pour la session même si l'écriture échoue.
    }
  }
}
