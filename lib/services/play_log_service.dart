import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/play_log_entry.dart';

/// Persistance du journal d'écoute en simple fichier JSON, comme l'historique
/// des rappels et les compteurs : pas de schéma Isar, donc pas de migration.
class PlayLogService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/play_log.json');
  }

  Future<List<PlayLogEntry>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final out = <PlayLogEntry>[];
      for (final raw in json['entries'] as List<dynamic>? ?? const []) {
        try {
          out.add(PlayLogEntry.fromJson(Map<String, dynamic>.from(raw as Map)));
        } catch (_) {
          // Une ligne abîmée ne doit pas faire perdre tout le journal.
        }
      }
      return out;
    } catch (_) {
      // Fichier absent ou corrompu : on repart d'un journal vide.
      return const [];
    }
  }

  Future<void> save(List<PlayLogEntry> entries) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'v': 1,
        'entries': entries.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {
      // L'état en mémoire reste valable pour la session.
    }
  }
}
