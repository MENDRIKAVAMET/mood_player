import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// Crée la vidéo MP4 d'un extrait (image fixe + audio) via le code natif
/// Android (MediaCodec / MediaMuxer), sans ffmpeg.
class ExcerptService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mood_player/files');

  /// Durée maximale d'un extrait.
  static const int excerptMs = 10000;

  /// [pngBytes] : carte exportée en PNG. Renvoie le chemin du MP4.
  static Future<String> createVideo({
    required Track track,
    required Uint8List pngBytes,
    required int startMs,
    required int durationMs,
  }) async {
    if (track.uri == null && track.filePath == null) {
      throw StateError('source audio introuvable');
    }
    final dir = await getTemporaryDirectory();
    await _cleanOld(dir);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final png = File('${dir.path}/aura_extrait_$stamp.png');
    final outputPath = '${dir.path}/aura_extrait_$stamp.mp4';
    try {
      await png.writeAsBytes(pngBytes, flush: true);
      final path = await _channel.invokeMethod<String>('createExcerptVideo', {
        'uri': track.uri,
        'path': track.filePath,
        'imagePath': png.path,
        'startMs': startMs,
        'durationMs': durationMs,
        'outputPath': outputPath,
      }).timeout(const Duration(seconds: 150));
      if (path == null) throw StateError('vidéo non créée');
      return path;
    } finally {
      // Le PNG temporaire n'est plus utile une fois la vidéo faite.
      try {
        if (await png.exists()) await png.delete();
      } catch (_) {}
    }
  }

  /// Supprime les anciens extraits (vidéos et PNG) laissés dans le cache.
  static Future<void> _cleanOld(Directory dir) async {
    try {
      await for (final e in dir.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith('aura_extrait_')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
