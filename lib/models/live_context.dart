import 'track.dart';

enum WeatherCondition { clear, cloudy, fog, rain, snow, storm }

/// Météo du moment à l'endroit choisi par l'utilisateur.
class WeatherInfo {
  final WeatherCondition condition;
  final double tempC;
  final bool isDay;
  final DateTime fetchedAt;

  const WeatherInfo({
    required this.condition,
    required this.tempC,
    required this.isDay,
    required this.fetchedAt,
  });

  String get label {
    switch (condition) {
      case WeatherCondition.clear:
        return 'Ciel dégagé';
      case WeatherCondition.cloudy:
        return 'Nuageux';
      case WeatherCondition.fog:
        return 'Brouillard';
      case WeatherCondition.rain:
        return 'Pluie';
      case WeatherCondition.snow:
        return 'Neige';
      case WeatherCondition.storm:
        return 'Orage';
    }
  }
}

/// Ce que dit l'accéléromètre pendant quelques secondes. [unknown] quand le
/// signal est ambigu (téléphone en main, transport...) : on ne devine pas.
enum MotionState { unknown, still, moving }

/// Tout ce que l'app sait du moment présent.
class LiveContext {
  final DateTime now;
  final WeatherInfo? weather;
  final MotionState motion;

  /// Casque filaire, Bluetooth ou USB branché.
  final bool headphones;

  /// Nom de la ville choisie pour la météo, null si aucune.
  final String? placeName;

  /// La météo a été demandée mais n'a pas pu être récupérée.
  final bool weatherFailed;

  /// La détection de mouvement est activée dans les réglages.
  final bool motionEnabled;

  const LiveContext({
    required this.now,
    this.weather,
    this.motion = MotionState.unknown,
    this.headphones = false,
    this.placeName,
    this.weatherFailed = false,
    this.motionEnabled = true,
  });
}

/// Ambiances proposées pour le moment présent, avec la raison.
class LiveSuggestion {
  final String title;
  final String reason;

  /// 1 à 3 ambiances ; la plus pertinente vaut 1.0.
  final Map<MoodType, double> weights;

  const LiveSuggestion({
    required this.title,
    required this.reason,
    required this.weights,
  });
}
