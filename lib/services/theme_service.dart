import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;
import 'package:path_provider/path_provider.dart';

/// Persiste le choix de thème dans un petit fichier JSON local, comme le
/// profil : deux ou trois valeurs lues/réécrites en bloc, pas besoin d'un
/// schéma Isar.
///
/// Singleton : `main()` le charge avant `runApp` pour que le tout premier
/// affichage ait déjà la bonne couleur de fond (pas de flash du thème
/// d'origine au démarrage).
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  Color? _background;

  /// Couleur de fond choisie, ou null = thème d'origine.
  Color? get background => _background;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/theme_settings.json');
  }

  Future<Color?> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final value = json is Map ? json['background'] : null;
        _background = value is int ? Color(value) : null;
      }
    } catch (_) {
      // Fichier absent ou corrompu : thème d'origine plutôt que de bloquer
      // le démarrage pour une préférence d'affichage.
      _background = null;
    }
    return _background;
  }

  Future<void> save(Color? background) async {
    _background = background;
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({'background': background?.toARGB32()}),
      );
    } catch (_) {
      // Le choix reste valable pour la session même si l'écriture échoue.
    }
  }
}
