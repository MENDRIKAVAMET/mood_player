import 'dart:io';
import 'dart:typed_data';

import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

/// Récupère les pochettes que le téléphone connaît déjà et les met en cache
/// sur disque.
///
/// Les miniatures dont tu parles ne sont pas des fichiers séparés rangés
/// quelque part : Android les extrait des tags du fichier audio lui-même
/// (bloc APIC d'un MP3, atome `covr` d'un M4A…) et les expose via
/// MediaStore. Impossible d'y accéder par un chemin de fichier — il faut
/// passer par `queryArtwork(mediaStoreId)`. D'où ce service.
///
/// Le résultat est écrit une fois dans le cache de l'app puis réutilisé :
/// les appels natifs sont lents (~10-30 ms chacun), et une bibliothèque de
/// 300 titres ne doit pas les repayer à chaque ouverture. Un simple test
/// d'existence de fichier suffit ensuite.
class ArtworkService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Directory? _cacheDir;

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/artwork');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  String _fileNameFor(int mediaStoreId) => 'art_$mediaStoreId.jpg';

  /// Chemin du fichier de cache s'il existe déjà, sinon null. Purement
  /// local : aucun appel natif, donc utilisable en boucle sur toute la
  /// bibliothèque.
  Future<String?> cachedPath(int mediaStoreId) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_fileNameFor(mediaStoreId)}');
    return await file.exists() ? file.path : null;
  }

  /// Marqueur « ce morceau n'a pas de pochette ». Sans lui, chaque scan
  /// retenterait l'extraction sur les mêmes fichiers sans pochette.
  Future<bool> _isKnownEmpty(int mediaStoreId) async {
    final dir = await _dir();
    return File('${dir.path}/art_$mediaStoreId.none').exists();
  }

  /// Extrait la pochette et l'écrit dans le cache. Renvoie le chemin, ou
  /// null si le morceau n'en a pas.
  Future<String?> extract(int mediaStoreId) async {
    final existing = await cachedPath(mediaStoreId);
    if (existing != null) return existing;
    if (await _isKnownEmpty(mediaStoreId)) return null;

    final dir = await _dir();
    try {
      final Uint8List? bytes = await _audioQuery.queryArtwork(
        mediaStoreId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        // 512 px : assez net pour le grand lecteur et l'écran verrouillé,
        // assez léger pour 300+ fichiers en cache.
        size: 512,
        quality: 90,
      );

      if (bytes == null || bytes.isEmpty) {
        await File('${dir.path}/art_$mediaStoreId.none').writeAsString('');
        return null;
      }

      final file = File('${dir.path}/${_fileNameFor(mediaStoreId)}');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      // Fichier corrompu, tag illisible, plugin qui tousse : pas de
      // pochette, ce n'est pas une raison pour casser le scan.
      return null;
    }
  }

  /// Extrait les pochettes manquantes d'un lot de morceaux.
  ///
  /// Séquentiel et non parallèle : `queryArtwork` passe par un seul canal
  /// de méthode, le paralléliser ne gagne rien et sature le thread UI.
  /// [onProgress] est appelé à chaque pochette effectivement trouvée, pour
  /// que l'écran puisse se rafraîchir au fil de l'eau plutôt qu'à la fin.
  Future<void> extractBatch(
    Iterable<int> mediaStoreIds, {
    void Function(int mediaStoreId, String path)? onProgress,
  }) async {
    for (final id in mediaStoreIds) {
      final path = await extract(id);
      if (path != null) onProgress?.call(id, path);
    }
  }
}
