// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/live_context.dart';
import 'weather_service.dart';

/// Réglages du mood live : ville pour la météo et détection de mouvement.
class LiveSettings {
  final bool motionEnabled;
  final String? city;
  final double? lat;
  final double? lon;

  const LiveSettings({
    this.motionEnabled = true,
    this.city,
    this.lat,
    this.lon,
  });

  bool get hasPlace => city != null && lat != null && lon != null;

  LiveSettings copyWith({
    bool? motionEnabled,
    String? city,
    double? lat,
    double? lon,
  }) =>
      LiveSettings(
        motionEnabled: motionEnabled ?? this.motionEnabled,
        city: city ?? this.city,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
      );

  LiveSettings withoutPlace() => LiveSettings(motionEnabled: motionEnabled);

  Map<String, dynamic> toJson() => {
        'motion': motionEnabled,
        if (city != null) 'city': city,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
      };

  factory LiveSettings.fromJson(Map<String, dynamic> json) => LiveSettings(
        motionEnabled: json['motion'] as bool? ?? true,
        city: json['city'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
      );
}

/// Persistance des réglages : petit fichier JSON local, comme le profil.
class LiveSettingsService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/live_mood.json');
  }

  Future<LiveSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const LiveSettings();
      final json = jsonDecode(await file.readAsString());
      return LiveSettings.fromJson(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return const LiveSettings();
    }
  }

  Future<void> save(LiveSettings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Les réglages en mémoire restent valables pour la session.
    }
  }
}

/// Détecte si le téléphone bouge, en lisant l'accéléromètre quelques
/// secondes, uniquement à la demande (jamais en continu : pas de batterie
/// consommée en arrière-plan).
class MotionSampler {
  /// Sous ce seuil (m/s², accélération hors gravité), le téléphone est
  /// posé ou presque.
  static const double stillBelow = 0.4;

  /// Au-dessus, il est porté en marchant ou en courant. Entre les deux, le
  /// signal est ambigu (téléphone en main, véhicule) : [MotionState.unknown].
  static const double movingFrom = 0.8;

  static const int minSamples = 10;

  /// Classe une série d'accélérations (norme, hors gravité).
  static MotionState classify(List<double> magnitudes) {
    if (magnitudes.length < minSamples) return MotionState.unknown;
    var sumSquares = 0.0;
    for (final m in magnitudes) {
      sumSquares += m * m;
    }
    final rms = math.sqrt(sumSquares / magnitudes.length);
    if (rms >= movingFrom) return MotionState.moving;
    if (rms < stillBelow) return MotionState.still;
    return MotionState.unknown;
  }

  Future<MotionState> sample({
    Duration duration = const Duration(seconds: 3),
  }) async {
    final magnitudes = <double>[];
    try {
      final sub = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(
        (e) => magnitudes.add(math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z)),
        onError: (_) {},
      );
      await Future<void>.delayed(duration);
      await sub.cancel();
    } catch (_) {
      return MotionState.unknown;
    }
    return classify(magnitudes);
  }
}

/// Casque filaire, Bluetooth ou USB actuellement branché comme sortie audio.
class HeadphoneDetector {
  // AudioDeviceType est marqué expérimental par audio_session, mais c'est
  // l'API prévue pour lister les sorties audio.
  static const _types = {
    AudioDeviceType.wiredHeadset,
    AudioDeviceType.wiredHeadphones,
    AudioDeviceType.bluetoothA2dp,
    AudioDeviceType.bluetoothLe,
    AudioDeviceType.usbAudio,
  };

  static Future<bool> connected() async {
    try {
      final session = await AudioSession.instance;
      final devices = await session.getDevices(includeInputs: false);
      return devices.any((d) => d.isOutput && _types.contains(d.type));
    } catch (_) {
      return false;
    }
  }
}

/// Rassemble tout ce qui décrit le moment présent.
class LiveContextService {
  final LiveSettingsService settingsService;
  final WeatherService weather;
  final MotionSampler motion;

  WeatherInfo? _cached;
  String? _cachedKey;

  /// Une météo récupérée il y a moins de 30 minutes est réutilisée.
  static const Duration weatherTtl = Duration(minutes: 30);

  LiveContextService({
    LiveSettingsService? settingsService,
    WeatherService? weather,
    MotionSampler? motion,
  })  : settingsService = settingsService ?? LiveSettingsService(),
        weather = weather ?? WeatherService(),
        motion = motion ?? MotionSampler();

  void clearWeatherCache() {
    _cached = null;
    _cachedKey = null;
  }

  Future<LiveContext> gather({DateTime? now}) async {
    final settings = await settingsService.load();
    final moment = now ?? DateTime.now();

    final weatherFuture = _weatherFor(settings);
    final motionFuture = settings.motionEnabled
        ? motion.sample()
        : Future.value(MotionState.unknown);
    final headphonesFuture = HeadphoneDetector.connected();

    final (info, failed) = await weatherFuture;
    return LiveContext(
      now: moment,
      weather: info,
      weatherFailed: failed,
      motion: await motionFuture,
      headphones: await headphonesFuture,
      placeName: settings.city,
      motionEnabled: settings.motionEnabled,
    );
  }

  Future<(WeatherInfo?, bool)> _weatherFor(LiveSettings s) async {
    if (!s.hasPlace) return (null, false);
    final key = '${s.lat},${s.lon}';
    final cached = _cached;
    final sameKey = _cachedKey == key;
    if (cached != null &&
        sameKey &&
        DateTime.now().difference(cached.fetchedAt) < weatherTtl) {
      return (cached, false);
    }
    try {
      final fresh = await weather.current(s.lat!, s.lon!);
      _cached = fresh;
      _cachedKey = key;
      return (fresh, false);
    } catch (_) {
      // Hors ligne : on garde la dernière météo connue si elle date du
      // même endroit, sinon on continue sans.
      return (sameKey ? cached : null, true);
    }
  }
}
