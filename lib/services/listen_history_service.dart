import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/listen_event.dart';

/// Contenu du fichier d'historique : les écoutes retenues et les rappels
/// déjà présentés (pour ne jamais afficher deux fois le même).
class ListenHistoryData {
  final List<ListenEvent> events;
  final Set<String> shown;

  const ListenHistoryData({this.events = const [], this.shown = const {}});
}

/// Persistance en simple fichier JSON, comme le profil et les compteurs
/// d'écoute : pas de schéma Isar, donc pas de migration de base.
class ListenHistoryService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/listen_history.json');
  }

  Future<ListenHistoryData> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const ListenHistoryData();
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return ListenHistoryData(
        events: (json['events'] as List<dynamic>? ?? const [])
            .map((e) => ListenEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        shown: (json['shown'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toSet(),
      );
    } catch (_) {
      // Fichier absent ou corrompu : on repart d'un historique vide.
      return const ListenHistoryData();
    }
  }

  Future<void> save(ListenHistoryData data) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'events': data.events.map((e) => e.toJson()).toList(),
        'shown': data.shown.toList(),
      }));
    } catch (_) {
      // L'état en mémoire reste valable pour la session.
    }
  }
}
