import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/live_context.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/live_context_service.dart';
import 'package:mood_player/services/live_mood_engine.dart';
import 'package:mood_player/services/weather_service.dart';

WeatherInfo _w(WeatherCondition c, {double t = 20, bool day = true}) =>
    WeatherInfo(
      condition: c,
      tempC: t,
      isDay: day,
      fetchedAt: DateTime(2026, 11, 17),
    );

void main() {
  // Mardi 17 novembre 2026.
  DateTime at(int hour) => DateTime(2026, 11, 17, hour);

  group('WeatherService.conditionFromCode', () {
    test('codes WMO', () {
      expect(WeatherService.conditionFromCode(0), WeatherCondition.clear);
      expect(WeatherService.conditionFromCode(1), WeatherCondition.clear);
      expect(WeatherService.conditionFromCode(3), WeatherCondition.cloudy);
      expect(WeatherService.conditionFromCode(45), WeatherCondition.fog);
      expect(WeatherService.conditionFromCode(61), WeatherCondition.rain);
      expect(WeatherService.conditionFromCode(81), WeatherCondition.rain);
      expect(WeatherService.conditionFromCode(73), WeatherCondition.snow);
      expect(WeatherService.conditionFromCode(95), WeatherCondition.storm);
    });
  });

  group('MotionSampler.classify', () {
    test('posé, en marche, ambigu, pas assez de mesures', () {
      expect(MotionSampler.classify(List.filled(40, 0.05)), MotionState.still);
      expect(MotionSampler.classify(List.filled(40, 1.6)), MotionState.moving);
      expect(MotionSampler.classify(List.filled(40, 0.6)), MotionState.unknown);
      expect(MotionSampler.classify(List.filled(5, 2.0)), MotionState.unknown);
    });
  });

  group('LiveMoodEngine.suggest', () {
    test('pluie le soir : Chill en tête, Mélancolique présent', () {
      final s = LiveMoodEngine.suggest(LiveContext(
        now: at(21),
        weather: _w(WeatherCondition.rain),
      ));
      expect(s.weights.keys.first, MoodType.chill);
      expect(s.weights.containsKey(MoodType.melancholic), true);
      expect(s.title, 'Ambiance pluie');
      expect(s.reason.toLowerCase(), contains('il pleut'));
      expect(s.reason, contains('il est 21 h'));
    });

    test('en mouvement le matin : Motivant en tête', () {
      final s = LiveMoodEngine.suggest(LiveContext(
        now: at(8),
        motion: MotionState.moving,
      ));
      expect(s.weights.keys.first, MoodType.motivating);
      expect(s.weights.containsKey(MoodType.energetic), true);
      expect(s.title, 'En mouvement');
    });

    test('nuit au calme : Sommeil en tête', () {
      final s = LiveMoodEngine.suggest(LiveContext(
        now: at(23),
        motion: MotionState.still,
      ));
      expect(s.weights.keys.first, MoodType.sleep);
      expect(s.title, 'Pour la nuit');
    });

    test('en mouvement la nuit : Sommeil rétrogradé', () {
      final s = LiveMoodEngine.suggest(LiveContext(
        now: at(23),
        motion: MotionState.moving,
      ));
      expect(s.weights.keys.first, isNot(MoodType.sleep));
    });

    test('grand soleil l\'après-midi : Festif parmi les ambiances', () {
      final s = LiveMoodEngine.suggest(LiveContext(
        now: at(14),
        weather: _w(WeatherCondition.clear, t: 33),
      ));
      expect(s.weights.containsKey(MoodType.festive), true);
      expect(s.title, 'Grand soleil');
      expect(s.reason, contains('33°'));
    });

    test('sans météo : fonctionne quand même', () {
      final s = LiveMoodEngine.suggest(LiveContext(now: at(10)));
      expect(s.weights, isNotEmpty);
      expect(s.reason.toLowerCase(), contains('il est 10 h'));
    });

    test('au plus 3 ambiances, la première vaut 1.0', () {
      final s = LiveMoodEngine.suggest(LiveContext(
        now: at(21),
        weather: _w(WeatherCondition.rain),
        motion: MotionState.moving,
        headphones: true,
      ));
      expect(s.weights.length, lessThanOrEqualTo(3));
      expect(s.weights.values.first, 1.0);
      expect(s.weights.values.every((v) => v >= 0.3 && v <= 1.0), true);
    });
  });

  test('mix : seulement les ambiances proposées, 20 morceaux', () {
    final library = [
      for (var i = 1; i <= 60; i++)
        Track()
          ..id = i
          ..title = 'T$i'
          ..artist = 'A'
          ..mood = i <= 40 ? MoodType.chill : MoodType.energetic,
    ];
    const suggestion = LiveSuggestion(
      title: 't',
      reason: 'r',
      weights: {MoodType.chill: 1.0},
    );
    final mix = LiveMoodEngine.mix(library, suggestion);
    expect(mix.length, 20);
    expect(mix.every((t) => t.mood == MoodType.chill), true);
  });

  test('LiveSettings : aller-retour JSON et ville retirée', () {
    const s = LiveSettings(
      motionEnabled: false,
      city: 'Fianarantsoa',
      lat: -21.45,
      lon: 47.08,
    );
    final back = LiveSettings.fromJson(s.toJson());
    expect(back.motionEnabled, false);
    expect(back.city, 'Fianarantsoa');
    expect(back.hasPlace, true);
    expect(s.withoutPlace().hasPlace, false);
    expect(s.withoutPlace().motionEnabled, false);
    expect(LiveSettings.fromJson(const {}).motionEnabled, true);
  });
}
