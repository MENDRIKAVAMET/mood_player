import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/mood_image_choice.dart';
import '../models/track.dart';

class _Entry {
  MoodImageSource source;
  String? file;
  _Entry(this.source, this.file);
}

/// Persiste le choix d'image de chaque ambiance (origine / animé / icône /
/// image importée).
///
/// Les images importées sont COPIÉES dans le dossier de l'application
/// (`mood_images/`) : si l'utilisateur supprime la photo d'origine de sa
/// galerie, l'ambiance garde son image. Le choix est stocké dans un petit
/// JSON (comme le thème et le profil) ; on n'y met que le nom du fichier,
/// pas le chemin absolu, qui peut changer d'une mise à jour à l'autre.
///
/// Une ambiance absente de la table est en « origine » (le défaut).
class MoodImageService {
  MoodImageService._();
  static final MoodImageService instance = MoodImageService._();

  static const _allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

  /// `MoodType.name` → choix.
  final Map<String, _Entry> _entries = {};
  String? _dirPath;

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'mood_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _dirPath = dir.path;
    return dir;
  }

  Future<File> _indexFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'mood_images.json'));
  }

  Map<MoodType, MoodImageChoice> _snapshot() {
    final result = <MoodType, MoodImageChoice>{};
    for (final mood in MoodType.values) {
      final entry = _entries[mood.name];
      if (entry == null) continue;
      final file = entry.file;
      result[mood] = MoodImageChoice(
        entry.source,
        customPath: (file != null && _dirPath != null)
            ? p.join(_dirPath!, file)
            : null,
      );
    }
    return result;
  }

  /// Lit les choix enregistrés. Une image importée dont le fichier a
  /// disparu est ignorée (retour à l'image d'origine).
  Future<Map<MoodType, MoodImageChoice>> load() async {
    _entries.clear();
    try {
      final dir = await _dir();
      final index = await _indexFile();
      if (await index.exists()) {
        final json = jsonDecode(await index.readAsString());
        if (json is Map) {
          for (final item in json.entries) {
            final key = item.key;
            if (key is! String || !MoodType.values.any((m) => m.name == key)) {
              continue;
            }
            final value = item.value;
            String? file;
            var source = MoodImageSource.original;
            if (value is String) {
              // Ancien format : « ambiance → nom du fichier importé ».
              file = value;
              source = MoodImageSource.custom;
            } else if (value is Map) {
              final f = value['file'];
              if (f is String) file = f;
              for (final s in MoodImageSource.values) {
                if (s.name == value['source']) source = s;
              }
            }
            if (file != null && !await File(p.join(dir.path, file)).exists()) {
              file = null;
            }
            if (source == MoodImageSource.custom && file == null) {
              source = MoodImageSource.original;
            }
            if (source == MoodImageSource.original && file == null) continue;
            _entries[key] = _Entry(source, file);
          }
        }
      }
    } catch (_) {
      // Index absent ou corrompu : on repart sur les images d'origine
      // plutôt que de bloquer l'écran pour une préférence d'affichage.
    }
    return _snapshot();
  }

  /// Choisit la source d'affichage de [mood]. `custom` est ignoré si
  /// aucune image n'a encore été importée pour cette ambiance.
  Future<Map<MoodType, MoodImageChoice>> setSource(
    MoodType mood,
    MoodImageSource source,
  ) async {
    await _dir();
    final entry = _entries[mood.name];
    if (source == MoodImageSource.custom && entry?.file == null) {
      return _snapshot();
    }
    _apply(mood, source);
    await _writeIndex();
    return _snapshot();
  }

  /// Applique [source] (origine, animé ou icône) à toutes les ambiances.
  /// Les images déjà importées restent stockées, prêtes à être réutilisées.
  Future<Map<MoodType, MoodImageChoice>> setSourceForAll(
    MoodImageSource source,
  ) async {
    await _dir();
    if (source == MoodImageSource.custom) return _snapshot();
    for (final mood in MoodType.values) {
      if (mood == MoodType.unknown) continue;
      _apply(mood, source);
    }
    await _writeIndex();
    return _snapshot();
  }

  void _apply(MoodType mood, MoodImageSource source) {
    final entry = _entries[mood.name];
    if (entry == null) {
      if (source != MoodImageSource.original) {
        _entries[mood.name] = _Entry(source, null);
      }
      return;
    }
    entry.source = source;
    if (source == MoodImageSource.original && entry.file == null) {
      _entries.remove(mood.name);
    }
  }

  /// Copie [sourcePath] dans le dossier de l'app, l'associe à [mood] et
  /// l'active. Lève une exception si ce n'est pas une image lisible (rien
  /// n'est alors modifié).
  Future<Map<MoodType, MoodImageChoice>> importImage(
    MoodType mood,
    String sourcePath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();

    // Vérifie que c'est bien une image décodable avant de remplacer
    // quoi que ce soit.
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    codec.dispose();

    final dir = await _dir();
    final ext = p.extension(sourcePath).toLowerCase();
    final safeExt = _allowedExtensions.contains(ext) ? ext : '.jpg';
    // Nom unique à chaque import : le cache d'images de Flutter est
    // indexé par chemin, un nom identique afficherait l'ancienne image.
    final fileName =
        '${mood.name}_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    await File(p.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);

    final entry = _entries.putIfAbsent(
      mood.name,
      () => _Entry(MoodImageSource.custom, null),
    );
    final previous = entry.file;
    entry.file = fileName;
    entry.source = MoodImageSource.custom;
    await _writeIndex();
    await _deleteQuietly(dir, previous);
    return _snapshot();
  }

  /// Supprime l'image importée de [mood] ; si elle était affichée, retour
  /// à l'image d'origine.
  Future<Map<MoodType, MoodImageChoice>> clearImported(MoodType mood) async {
    final dir = await _dir();
    final entry = _entries[mood.name];
    if (entry == null) return _snapshot();
    final previous = entry.file;
    entry.file = null;
    if (entry.source == MoodImageSource.custom) {
      entry.source = MoodImageSource.original;
    }
    if (entry.source == MoodImageSource.original) {
      _entries.remove(mood.name);
    }
    await _writeIndex();
    await _deleteQuietly(dir, previous);
    return _snapshot();
  }

  Future<void> _deleteQuietly(Directory dir, String? fileName) async {
    if (fileName == null) return;
    try {
      final file = File(p.join(dir.path, fileName));
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Un fichier orphelin n'est pas grave.
    }
  }

  Future<void> _writeIndex() async {
    try {
      final index = await _indexFile();
      await index.writeAsString(jsonEncode({
        for (final e in _entries.entries)
          e.key: {'source': e.value.source.name, 'file': e.value.file},
      }));
    } catch (_) {
      // Le choix reste valable pour la session même si l'écriture échoue.
    }
  }
}
