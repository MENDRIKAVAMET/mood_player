import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/equalizer_settings.dart';

/// Persiste les réglages de l'égaliseur dans un petit fichier JSON local
/// (même approche que le profil).
class EqualizerService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/equalizer.json');
  }

  Future<EqualizerSettings> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        return EqualizerSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(await file.readAsString())),
        );
      }
    } catch (_) {
      // Fichier absent ou corrompu : réglages par défaut.
    }
    return const EqualizerSettings();
  }

  Future<void> save(EqualizerSettings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Non critique : les réglages restent valables pour la session.
    }
  }
}
