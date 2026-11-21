import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// Crée la vidéo MP4 d'un extrait (suite d'images + audio) via le code natif
/// Android (MediaCodec / MediaMuxer), sans ffmpeg.
class ExcerptService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mood_player/files');

  /// Durée maximale d'un extrait.
  static const int excerptMs = 10000;

  /// Images par seconde du karaoké.
  static const int karaokeFps = 10;

  static const String _prefix = 'aura_extrait_';

  /// Dossier temporaire pour les images d'une nouvelle vidéo ; supprime au
  /// passage les restes des précédentes.
  static Future<({Directory dir, String stamp})> prepare() async {
    final dir = await getTemporaryDirectory();
    await _cleanOld(dir);
    return (dir: dir, stamp: DateTime.now().millisecondsSinceEpoch.toString());
  }

  /// Écrit une image (PNG) et renvoie son chemin.
  static Future<String> writeFrame(
    ({Directory dir, String stamp}) ctx,
    int index,
    Uint8List png,
  ) async {
    final f = File('${ctx.dir.path}/$_prefix${ctx.stamp}_$index.png');
    await f.writeAsBytes(png, flush: true);
    return f.path;
  }

  /// [imagePaths] : une image par trame, à [fps] images par seconde (le même
  /// chemin peut se répéter). Renvoie le chemin du MP4. Les images sont
  /// supprimées à la fin.
  static Future<String> createVideo({
    required Track track,
    required ({Directory dir, String stamp}) ctx,
    required List<String> imagePaths,
    required int fps,
    required int startMs,
    required int durationMs,
  }) async {
    if (track.uri == null && track.filePath == null) {
      throw StateError('source audio introuvable');
    }
    final outputPath = '${ctx.dir.path}/$_prefix${ctx.stamp}.mp4';
    try {
      final path = await _channel.invokeMethod<String>('createExcerptVideo', {
        'uri': track.uri,
        'path': track.filePath,
        'imagePaths': imagePaths,
        'fps': fps,
        'startMs': startMs,
        'durationMs': durationMs,
        'outputPath': outputPath,
      }).timeout(const Duration(seconds: 150));
      if (path == null) throw StateError('vidéo non créée');
      return path;
    } finally {
      for (final p in imagePaths.toSet()) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Supprime les anciens extraits (vidéos et PNG) laissés dans le cache.
  static Future<void> _cleanOld(Directory dir) async {
    try {
      await for (final e in dir.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith(_prefix)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
