import 'dart:math' as math;

import '../models/live_context.dart';
import '../models/track.dart';
import 'mood_query_parser.dart';

/// Règles qui transforment le contexte (heure, météo, mouvement, casque)
/// en ambiances à proposer. Ce sont des règles écrites à la main, pas de
/// l'apprentissage : « il pleut le soir » donne plutôt Chill et
/// Mélancolique, « tu bouges » donne plutôt Motivant et Énergique.
class LiveMoodEngine {
  LiveMoodEngine._();

  static LiveSuggestion suggest(LiveContext c) {
    final scores = <MoodType, double>{};
    void add(MoodType m, double v) => scores[m] = (scores[m] ?? 0) + v;

    final reasons = <String>[];
    final h = c.now.hour;
    final weekday = c.now.weekday; // 1 = lundi … 7 = dimanche

    // --- Heure ----------------------------------------------------------
    final isNight = h >= 22 || h < 5;
    String slotTitle;
    if (isNight) {
      add(MoodType.sleep, 0.6);
      add(MoodType.chill, 0.5);
      add(MoodType.melancholic, 0.3);
      slotTitle = 'Pour la nuit';
    } else if (h < 9) {
      add(MoodType.motivating, 0.7);
      add(MoodType.chill, 0.5);
      add(MoodType.energetic, 0.3);
      slotTitle = 'Pour bien commencer';
    } else if (h < 12) {
      add(MoodType.concentration, 0.6);
      add(MoodType.motivating, 0.5);
      add(MoodType.energetic, 0.3);
      slotTitle = 'Pour avancer';
    } else if (h < 14) {
      add(MoodType.energetic, 0.5);
      add(MoodType.motivating, 0.3);
      add(MoodType.festive, 0.2);
      slotTitle = 'Un coup de boost';
    } else if (h < 18) {
      add(MoodType.concentration, 0.5);
      add(MoodType.energetic, 0.4);
      add(MoodType.motivating, 0.3);
      slotTitle = 'Pour rester concentré';
    } else {
      add(MoodType.chill, 0.6);
      add(MoodType.romantic, 0.3);
      add(MoodType.nostalgic, 0.2);
      slotTitle = 'Pour se poser';
    }

    // --- Météo ----------------------------------------------------------
    String? weatherTitle;
    final w = c.weather;
    if (w != null) {
      switch (w.condition) {
        case WeatherCondition.rain:
          add(MoodType.melancholic, 0.5);
          add(MoodType.chill, 0.4);
          add(MoodType.nostalgic, 0.3);
          reasons.add('il pleut');
          weatherTitle = 'Ambiance pluie';
        case WeatherCondition.storm:
          add(MoodType.dark, 0.4);
          add(MoodType.melancholic, 0.3);
          add(MoodType.energetic, 0.1);
          reasons.add('il y a de l\'orage');
          weatherTitle = 'Orage dehors';
        case WeatherCondition.snow:
          add(MoodType.chill, 0.4);
          add(MoodType.romantic, 0.3);
          reasons.add('il neige');
        case WeatherCondition.fog:
          add(MoodType.melancholic, 0.3);
          add(MoodType.chill, 0.3);
          reasons.add('il y a du brouillard');
        case WeatherCondition.clear:
          if (w.isDay && w.tempC >= 28) {
            add(MoodType.festive, 0.4);
            add(MoodType.roadtrip, 0.3);
            add(MoodType.energetic, 0.2);
            reasons.add('il fait ${w.tempC.round()}°');
            weatherTitle = 'Grand soleil';
          } else if (w.isDay) {
            add(MoodType.motivating, 0.2);
            add(MoodType.roadtrip, 0.2);
            reasons.add('il fait beau');
          } else {
            add(MoodType.romantic, 0.2);
            add(MoodType.chill, 0.2);
            reasons.add('le ciel est dégagé');
          }
        case WeatherCondition.cloudy:
          add(MoodType.chill, 0.2);
          add(MoodType.nostalgic, 0.1);
          reasons.add('le ciel est couvert');
      }
      if (w.tempC <= 10) {
        add(MoodType.chill, 0.2);
        add(MoodType.romantic, 0.1);
        reasons.add('il fait frais');
      }
    }

    // --- Mouvement ------------------------------------------------------
    var moving = false;
    if (c.motion == MotionState.moving) {
      moving = true;
      add(MoodType.energetic, 0.5);
      add(MoodType.motivating, 0.4);
      add(MoodType.roadtrip, 0.3);
      if (scores.containsKey(MoodType.sleep)) {
        scores[MoodType.sleep] = scores[MoodType.sleep]! * 0.2;
      }
      if (scores.containsKey(MoodType.concentration)) {
        scores[MoodType.concentration] = scores[MoodType.concentration]! * 0.5;
      }
      reasons.add('tu es en mouvement');
    }

    // --- Casque ---------------------------------------------------------
    if (c.headphones) {
      add(MoodType.concentration, 0.1);
      reasons.add('tu écoutes au casque');
    } else {
      add(MoodType.festive, 0.1);
    }

    // --- Jour de la semaine --------------------------------------------
    final fridayEvening = weekday == 5 && h >= 18;
    final weekend = weekday >= 6;
    if (fridayEvening) {
      add(MoodType.festive, 0.3);
      reasons.add('c\'est vendredi soir');
    } else if (weekend) {
      add(MoodType.festive, 0.2);
      add(MoodType.roadtrip, 0.1);
      reasons.add('c\'est le week-end');
    }

    // --- Titre ----------------------------------------------------------
    String title;
    if (weatherTitle == 'Orage dehors' || weatherTitle == 'Ambiance pluie') {
      title = weatherTitle!;
    } else if (moving) {
      title = 'En mouvement';
    } else if (isNight) {
      title = slotTitle;
    } else if (fridayEvening) {
      title = 'Vendredi soir';
    } else if (weekend) {
      title = 'Week-end';
    } else if (weatherTitle != null) {
      title = weatherTitle;
    } else {
      title = slotTitle;
    }

    reasons.add('il est $h h');
    final sentence = reasons.join(', ');
    final reason = '${sentence[0].toUpperCase()}${sentence.substring(1)}.';

    // --- Les 3 meilleures ambiances, la première ramenée à 1.0 ----------
    final ranked = scores.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        return byScore != 0 ? byScore : a.key.index.compareTo(b.key.index);
      });
    final top = ranked.take(3).toList();
    final best = top.first.value;
    return LiveSuggestion(
      title: title,
      reason: reason,
      weights: {
        for (final e in top) e.key: math.max(0.3, e.value / best),
      },
    );
  }

  /// Mix de [size] morceaux pour la suggestion : tirés au hasard parmi les
  /// plus pertinents pour que deux mix successifs diffèrent.
  static List<Track> mix(
    List<Track> library,
    LiveSuggestion suggestion, {
    int size = 20,
    math.Random? random,
  }) {
    final ranked = MoodQuery(weights: suggestion.weights).rank(library);
    final pool = ranked.take(size * 3).toList()
      ..shuffle(random ?? math.Random());
    return pool.take(size).toList();
  }
}
