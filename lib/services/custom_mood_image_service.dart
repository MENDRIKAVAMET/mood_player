import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/custom_mood_image.dart';

class _Entry {
  CustomMoodImageKind kind;
  String? asset;
  String? file;
  _Entry(this.kind, {this.asset, this.file});
}

/// Persiste l'image de chaque mood créé par l'utilisateur.
///
/// Stocké dans un petit JSON à part, indexé par l'id du mood, plutôt que
/// dans le modèle Isar : ajouter un champ à `CustomMood` obligerait à
/// régénérer le code Isar et à migrer la base, pour une simple préférence
/// d'affichage.
///
/// Les images importées sont COPIÉES dans le dossier de l'app
/// (`custom_mood_images/`) : supprimer la photo d'origine de la galerie
/// ne casse pas le mood. On ne stocke que le nom du fichier, pas le chemin
/// absolu (qui peut changer d'une mise à jour à l'autre).
class CustomMoodImageService {
  CustomMoodImageService._();
  static final CustomMoodImageService instance = CustomMoodImageService._();

  static const _allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

  final Map<int, _Entry> _entries = {};
  String? _dirPath;

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'custom_mood_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _dirPath = dir.path;
    return dir;
  }

  Future<File> _indexFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'custom_mood_images.json'));
  }

  Map<int, CustomMoodImage> _snapshot() {
    final result = <int, CustomMoodImage>{};
    for (final e in _entries.entries) {
      final file = e.value.file;
      result[e.key] = CustomMoodImage(
        e.value.kind,
        assetPath: e.value.asset,
        customPath:
            (file != null && _dirPath != null) ? p.join(_dirPath!, file) : null,
      );
    }
    return result;
  }

  Future<Map<int, CustomMoodImage>> load() async {
    _entries.clear();
    try {
      final dir = await _dir();
      final index = await _indexFile();
      if (await index.exists()) {
        final json = jsonDecode(await index.readAsString());
        if (json is Map) {
          for (final item in json.entries) {
            final id = int.tryParse('${item.key}');
            final value = item.value;
            if (id == null || value is! Map) continue;

            var kind = CustomMoodImageKind.none;
            for (final k in CustomMoodImageKind.values) {
              if (k.name == value['kind']) kind = k;
            }
            final asset = value['asset'] is String ? value['asset'] as String : null;
            var file = value['file'] is String ? value['file'] as String : null;
            if (file != null && !await File(p.join(dir.path, file)).exists()) {
              file = null;
            }
            // Une image active qui a disparu : retour au dégradé.
            if (kind == CustomMoodImageKind.custom && file == null) {
              kind = CustomMoodImageKind.none;
            }
            if (kind == CustomMoodImageKind.asset && asset == null) {
              kind = CustomMoodImageKind.none;
            }
            if (kind == CustomMoodImageKind.none && file == null && asset == null) {
              continue;
            }
            _entries[id] = _Entry(kind, asset: asset, file: file);
          }
        }
      }
    } catch (_) {
      // Index absent ou corrompu : on repart sans image plutôt que de
      // bloquer l'écran pour une préférence d'affichage.
    }
    return _snapshot();
  }

  _Entry _entry(int id) =>
      _entries.putIfAbsent(id, () => _Entry(CustomMoodImageKind.none));

  void _prune(int id) {
    final e = _entries[id];
    if (e != null &&
        e.kind == CustomMoodImageKind.none &&
        e.file == null &&
        e.asset == null) {
      _entries.remove(id);
    }
  }

  /// Retire l'image du mood (retour au dégradé de couleur).
  Future<Map<int, CustomMoodImage>> setNone(int id) async {
    await _dir();
    _entry(id).kind = CustomMoodImageKind.none;
    _prune(id);
    await _writeIndex();
    return _snapshot();
  }

  /// Utilise une image fournie avec l'app ([asset] = chemin d'asset).
  Future<Map<int, CustomMoodImage>> setAsset(int id, String asset) async {
    await _dir();
    final e = _entry(id);
    e.kind = CustomMoodImageKind.asset;
    e.asset = asset;
    await _writeIndex();
    return _snapshot();
  }

  /// Réactive l'image déjà importée, si elle existe.
  Future<Map<int, CustomMoodImage>> useImported(int id) async {
    await _dir();
    final e = _entries[id];
    if (e?.file != null) {
      e!.kind = CustomMoodImageKind.custom;
      await _writeIndex();
    }
    return _snapshot();
  }

  /// Copie [sourcePath] dans le dossier de l'app et l'active pour ce mood.
  /// Lève une exception si ce n'est pas une image lisible (rien n'est alors
  /// modifié).
  Future<Map<int, CustomMoodImage>> importImage(
    int id,
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
    final fileName = 'mood${id}_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    await File(p.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);

    final e = _entry(id);
    final previous = e.file;
    e.file = fileName;
    e.kind = CustomMoodImageKind.custom;
    await _writeIndex();
    await _deleteQuietly(dir, previous);
    return _snapshot();
  }

  /// Supprime l'image importée ; si elle était affichée, retour au dégradé.
  Future<Map<int, CustomMoodImage>> clearImported(int id) async {
    final dir = await _dir();
    final e = _entries[id];
    if (e == null) return _snapshot();
    final previous = e.file;
    e.file = null;
    if (e.kind == CustomMoodImageKind.custom) e.kind = CustomMoodImageKind.none;
    _prune(id);
    await _writeIndex();
    await _deleteQuietly(dir, previous);
    return _snapshot();
  }

  /// À appeler quand le mood est supprimé : efface son image importée.
  Future<Map<int, CustomMoodImage>> forget(int id) async {
    final dir = await _dir();
    final e = _entries.remove(id);
    await _writeIndex();
    await _deleteQuietly(dir, e?.file);
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
          '${e.key}': {
            'kind': e.value.kind.name,
            'asset': e.value.asset,
            'file': e.value.file,
          },
      }));
    } catch (_) {
      // Le choix reste valable pour la session même si l'écriture échoue.
    }
  }
}
