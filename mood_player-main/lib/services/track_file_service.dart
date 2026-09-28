import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// Erreur de renommage avec un message directement affichable.
class TrackRenameException implements Exception {
  final String message;
  const TrackRenameException(this.message);

  @override
  String toString() => message;
}

/// Renomme le vrai fichier audio (pas seulement son nom dans l'app).
///
/// Sur Android, seul MediaStore peut renommer proprement un fichier de
/// musique : en changeant son nom d'affichage, le système déplace le
/// fichier sur le disque et garde le même identifiant (donc le même `uri`
/// pour le lecteur). Le côté natif est dans `MainActivity.kt` ; sur
/// Android 11+ il peut afficher la demande d'autorisation du système
/// « Autoriser Mood Player à modifier ce fichier ? ».
class TrackFileService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mood_player/files');

  /// Nom de fichier proposé pour [artist] et [title], extension d'origine
  /// conservée. Les caractères interdits dans un nom de fichier sont
  /// retirés.
  static String fileNameFor(Track track, String artist, String title) {
    final base = _sanitize('$artist - $title');
    return '$base${_extensionOf(track.filePath)}';
  }

  static String _extensionOf(String? path) {
    if (path == null) return '';
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    return (dot > slash && dot > 0) ? path.substring(dot) : '';
  }

  static String _sanitize(String name) {
    var s = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    s = s.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();
    if (s.length > 180) s = s.substring(0, 180).trim();
    return s;
  }

  /// Renomme le fichier de [track] en « artiste - titre.ext » et renvoie
  /// son nouveau chemin. Lève [TrackRenameException] en cas d'échec ; dans
  /// ce cas le fichier n'a pas été modifié.
  Future<String> renameAudio(
    Track track, {
    required String artist,
    required String title,
  }) async {
    final uri = track.uri;
    final oldPath = track.filePath;
    if (uri == null || uri.isEmpty || oldPath == null || oldPath.isEmpty) {
      throw const TrackRenameException(
        'Ce morceau n\'est pas indexé par le système : impossible de '
        'renommer son fichier.',
      );
    }

    final displayName = fileNameFor(track, artist, title);
    if (displayName.isEmpty || displayName == _extensionOf(oldPath)) {
      throw const TrackRenameException('Nom de fichier invalide.');
    }

    String? newPath;
    try {
      newPath = await _channel.invokeMethod<String>('renameAudio', {
        'uri': uri,
        'displayName': displayName,
        'title': title,
        'artist': artist,
      });
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'DENIED':
          throw const TrackRenameException(
            'Autorisation refusée : le fichier n\'a pas été modifié.',
          );
        case 'UNSUPPORTED':
          throw const TrackRenameException(
            'Renommer un fichier nécessite Android 10 ou plus récent.',
          );
        case 'NOT_FOUND':
          throw const TrackRenameException(
            'Fichier introuvable dans la bibliothèque du système.',
          );
        default:
          throw TrackRenameException(
            'Échec du renommage : ${e.message ?? e.code}',
          );
      }
    } on MissingPluginException {
      throw const TrackRenameException(
        'Le renommage n\'est pas disponible sur cette plateforme.',
      );
    }

    final slash = oldPath.lastIndexOf('/');
    final resolved = (newPath != null && newPath.isNotEmpty)
        ? newPath
        : '${slash > 0 ? oldPath.substring(0, slash) : ''}/$displayName';

    await _renameSiblingLrc(oldPath, resolved);
    return resolved;
  }

  /// Le `.lrc` posé à côté du morceau porte son ancien nom : sans le
  /// renommer aussi, l'app ne retrouverait plus les paroles. Meilleur
  /// effort : ça dépend de l'accès aux fichiers, et un échec ici ne doit
  /// pas annuler un renommage déjà réussi.
  Future<void> _renameSiblingLrc(String oldPath, String newPath) async {
    try {
      String baseOf(String p) {
        final dot = p.lastIndexOf('.');
        final slash = p.lastIndexOf('/');
        return (dot > slash && dot > 0) ? p.substring(0, dot) : p;
      }

      final oldBase = baseOf(oldPath);
      final newBase = baseOf(newPath);
      if (oldBase == newBase) return;
      for (final ext in ['.lrc', '.LRC']) {
        final lrc = File('$oldBase$ext');
        if (await lrc.exists() && !await File('$newBase$ext').exists()) {
          await lrc.rename('$newBase$ext');
          return;
        }
      }
    } catch (_) {
      // Ignoré volontairement, voir ci-dessus.
    }
  }
}

/// Titre et artiste choisis par l'utilisateur, gardés par chemin de fichier.
///
/// Le renommage change bien MediaStore et le fichier, mais les tags
/// internes du fichier (ID3...) gardent l'ancien titre/artiste : si le
/// système réindexe le fichier, il peut les relire. Ces valeurs servent à
/// ce que le scan de la bibliothèque, qui met à jour les morceaux à chaque
/// ouverture, ne remette jamais l'ancien nom.
class TrackNameOverrides {
  static Map<String, Map<String, String>>? _cache;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/track_name_overrides.json');
  }

  static Future<Map<String, Map<String, String>>> load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _cache = {
          for (final e in decoded.entries)
            e.key: Map<String, String>.from(e.value as Map),
        };
      } else {
        _cache = {};
      }
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static Future<void> set({
    String? oldPath,
    required String newPath,
    required String title,
    required String artist,
  }) async {
    final map = await load();
    if (oldPath != null) map.remove(oldPath);
    map[newPath] = {'title': title, 'artist': artist};
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(map));
    } catch (_) {
      // Le cache mémoire garde la valeur pour la session.
    }
  }
}
