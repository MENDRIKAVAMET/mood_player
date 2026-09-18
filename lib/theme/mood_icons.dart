import 'package:flutter/material.dart';

/// Icônes proposées pour un mood personnalisé, et correspondance entre la
/// clé stockée (`CustomMood.icon`) et l'`IconData` à afficher.
///
/// Le champ reste un `String` en base — aucune migration Isar nécessaire —
/// mais son contenu change de sens : il contenait un glyphe emoji
/// (« 🔥ˮ), il contient maintenant une clé stable (« fireˮ). Les anciens
/// moods créés avant ce changement gardent leur emoji en base ;
/// [iconDataForKey] le reconnaît et le fait pointer vers l'icône
/// Material la plus proche, donc rien ne casse pour les moods existants.
class MoodIcons {
  MoodIcons._();

  static const Map<String, IconData> byKey = {
    'music': Icons.music_note_rounded,
    'fire': Icons.local_fire_department_rounded,
    'sleep': Icons.bedtime_rounded,
    'sad': Icons.cloud_rounded,
    'party': Icons.celebration_rounded,
    'heart': Icons.favorite_rounded,
    'brain': Icons.psychology_alt_rounded,
    'strength': Icons.fitness_center_rounded,
    'moon': Icons.nightlight_round,
    'bolt': Icons.bolt_rounded,
    'headphones': Icons.headphones_rounded,
    'flower': Icons.local_florist_rounded,
    'sun': Icons.wb_sunny_rounded,
    'rain': Icons.water_drop_rounded,
    'car': Icons.directions_car_filled_rounded,
    'book': Icons.menu_book_rounded,
  };

  /// Anciens glyphes emoji, pour que les moods créés avant le passage aux
  /// icônes Material continuent d'afficher quelque chose de cohérent.
  static const Map<String, String> _legacyEmojiToKey = {
    '🎵': 'music',
    '🔥': 'fire',
    '💤': 'sleep',
    '😢': 'sad',
    '🎉': 'party',
    '💖': 'heart',
    '🧠': 'brain',
    '💪': 'strength',
    '🌙': 'moon',
    '⚡': 'bolt',
    '🎧': 'headphones',
    '🌸': 'flower',
    '☀️': 'sun',
    '🌧️': 'rain',
    '🚗': 'car',
    '📚': 'book',
  };

  /// Clé par défaut proposée à la création d'un mood.
  static const String defaultKey = 'music';

  static IconData iconDataForKey(String key) {
    return byKey[key] ??
        byKey[_legacyEmojiToKey[key]] ??
        Icons.music_note_rounded;
  }
}
