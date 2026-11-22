import 'package:dio/dio.dart';

import '../models/live_context.dart';

/// Un lieu trouvé par la recherche de ville.
class GeoPlace {
  final String name;
  final String? country;
  final double lat;
  final double lon;

  const GeoPlace({
    required this.name,
    required this.lat,
    required this.lon,
    this.country,
  });

  String get label => country == null ? name : '$name, $country';
}

/// Météo via Open-Meteo (gratuit, sans clé). L'utilisateur choisit une
/// ville par son nom : pas de permission de localisation, et seules les
/// coordonnées de la ville (pas celles du téléphone) quittent l'appareil.
class WeatherService {
  final Dio _dio;

  WeatherService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  /// Premier résultat de la recherche, ou null si la ville est inconnue.
  Future<GeoPlace?> geocode(String city) async {
    final response = await _dio.get(
      'https://geocoding-api.open-meteo.com/v1/search',
      queryParameters: {
        'name': city.trim(),
        'count': 1,
        'language': 'fr',
        'format': 'json',
      },
    );
    final results = response.data['results'];
    if (results is! List || results.isEmpty) return null;
    final r = results.first as Map;
    final lat = r['latitude'];
    final lon = r['longitude'];
    final name = r['name'];
    if (lat is! num || lon is! num || name is! String) return null;
    return GeoPlace(
      name: name,
      country: r['country'] as String?,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
    );
  }

  Future<WeatherInfo> current(double lat, double lon) async {
    final response = await _dio.get(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': lat,
        'longitude': lon,
        'current': 'temperature_2m,weather_code,is_day',
        'timezone': 'auto',
      },
    );
    final cur = response.data['current'] as Map;
    return WeatherInfo(
      condition: conditionFromCode((cur['weather_code'] as num).toInt()),
      tempC: (cur['temperature_2m'] as num).toDouble(),
      isDay: (cur['is_day'] as num?) != 0,
      fetchedAt: DateTime.now(),
    );
  }

  /// Codes météo WMO utilisés par Open-Meteo.
  static WeatherCondition conditionFromCode(int code) {
    if (code >= 95) return WeatherCondition.storm;
    if (code == 45 || code == 48) return WeatherCondition.fog;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return WeatherCondition.snow;
    }
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
      return WeatherCondition.rain;
    }
    if (code == 2 || code == 3) return WeatherCondition.cloudy;
    return WeatherCondition.clear; // 0 et 1
  }
}
