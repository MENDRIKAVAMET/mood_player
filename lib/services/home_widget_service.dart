import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/track.dart';
import '../theme/mood_colors.dart';
import '../widgets/mood_ghost.dart';

/// Envoie au widget d'écran d'accueil (voir AuraWidgetProvider.kt) le
/// morceau en cours, son ambiance, l'état de lecture et le fantôme.
class HomeWidgetService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mood_player/widget');

  // Le PNG du fantôme n'est recalculé et renvoyé que s'il change.
  static MoodType? _ghostMood;
  static bool? _ghostPlaying;
  static bool _ghostSent = false;

  /// [title] null = rien en lecture.
  static Future<void> update({
    required String? title,
    String artist = '',
    MoodType? mood,
    required bool playing,
  }) async {
    try {
      final m = (mood == null || mood == MoodType.unknown) ? null : mood;
      Uint8List? ghost;
      if (!_ghostSent || _ghostMood != m || _ghostPlaying != playing) {
        ghost = await renderGhostPng(mood: m, playing: playing);
        _ghostMood = m;
        _ghostPlaying = playing;
        _ghostSent = true;
      }
      await _channel.invokeMethod<bool>('update', {
        'title': title,
        'artist': artist,
        'mood': m?.displayName ?? '',
        'playing': playing,
        'color': MoodColors.forMood(m).primary.toARGB32(),
        if (ghost != null) 'ghost': ghost,
      });
    } catch (_) {
      // Pas de widget ou plateforme sans widget : sans importance.
      _ghostSent = false;
    }
  }
}
