import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

/// Mesure et mémorise le volume moyen (dBFS, RMS) de chaque morceau pour la
/// fonction « Volume uniforme ». La mesure est faite côté Android
/// (MainActivity.measureLoudness) ; les résultats sont gardés dans un
/// fichier JSON pour ne jamais analyser deux fois le même fichier.
class LoudnessService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mood_player/files');

  /// Volume visé (dBFS RMS) : un compromis entre la musique commerciale
  /// récente (très forte, vers -10) et les enregistrements calmes (-20).
  static const double targetDb = -14;

  /// Atténuation maximale / renforcement maximal appliqués à un morceau.
  /// Le renforcement est limité pour éviter la saturation.
  static const double minGainDb = -12;
  static const double maxGainDb = 6;

  /// Valeur mémorisée pour un fichier qui n'a pas pu être analysé, afin de
  /// ne pas réessayer à chaque lancement.
  static const double _failed = 1000;

  static Map<String, double>? _cache;
  static int _unsaved = 0;

  /// Clé de mémorisation : chemin du fichier, sinon URI.
  static String? keyFor(String? filePath, String? uri) =>
      (filePath != null && filePath.isNotEmpty) ? filePath : uri;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/loudness.json');
  }

  static Future<Map<String, double>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _cache = {
          for (final e in decoded.entries) e.key: (e.value as num).toDouble(),
        };
        return _cache!;
      }
    } catch (_) {}
    return _cache = {};
  }

  /// Volume mesuré, ou null si inconnu / non analysable.
  static Future<double?> measured(String? key) async {
    if (key == null) return null;
    final v = (await _load())[key];
    return (v == null || v >= _failed) ? null : v;
  }

  /// Vrai si le fichier a déjà été traité (avec ou sans succès).
  static Future<bool> isKnown(String? key) async =>
      key != null && (await _load()).containsKey(key);

  /// Gain (dB) à appliquer à un morceau de volume mesuré [measuredDb].
  static double gainFor(double measuredDb) =>
      (targetDb - measuredDb).clamp(minGainDb, maxGainDb).toDouble();

  /// Analyse un morceau et mémorise le résultat.
  static Future<void> analyze(Track track) async {
    final key = keyFor(track.filePath, track.uri);
    if (key == null) return;
    double? value;
    try {
      value = await _channel.invokeMethod<double>('analyzeLoudness', {
        'uri': track.uri,
        'path': track.filePath,
      });
    } catch (_) {
      value = null;
    }
    final cache = await _load();
    cache[key] = value ?? _failed;
    if (++_unsaved >= 20) await flush();
  }

  static Future<void> flush() async {
    if (_cache == null || _unsaved == 0) return;
    _unsaved = 0;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(_cache));
    } catch (_) {}
  }
}
