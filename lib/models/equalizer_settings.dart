/// Réglages de l'égaliseur, indépendants du nombre de bandes de l'appareil
/// (4 à 6 selon les téléphones) : les préréglages sont des courbes à 5
/// points, rééchantillonnées sur le nombre réel de bandes.
class EqualizerPreset {
  final String name;

  /// Gain en dB à 5 points répartis du grave à l'aigu.
  final List<double> curve;

  const EqualizerPreset(this.name, this.curve);
}

class EqualizerSettings {
  static const String customName = 'Personnalisé';

  static const List<EqualizerPreset> presets = [
    EqualizerPreset('Neutre', [0, 0, 0, 0, 0]),
    EqualizerPreset('Basses', [6, 4, 0, 0, 0]),
    EqualizerPreset('Aigus', [0, 0, 0, 3, 6]),
    EqualizerPreset('Voix', [-2, 0, 3, 3, 0]),
    EqualizerPreset('Rock', [4, 2, -1, 2, 4]),
    EqualizerPreset('Pop', [-1, 2, 4, 2, -1]),
    EqualizerPreset('Jazz', [3, 1, -1, 1, 3]),
    EqualizerPreset('Classique', [3, 2, -1, 2, 3]),
    EqualizerPreset('Électro', [5, 3, 0, 2, 4]),
    EqualizerPreset('Hip-hop', [5, 4, 0, 1, 3]),
  ];

  /// Renforcement du volume maximal proposé (dB).
  static const double maxLoudnessDb = 8;

  final bool enabled;

  /// Nom d'un préréglage, ou [customName].
  final String preset;

  /// Gains personnalisés (dB), un par bande de l'appareil au moment de la
  /// sauvegarde. Vide = pas encore réglé.
  final List<double> gains;

  /// Renforcement du volume (dB, 0 = désactivé).
  final double loudnessDb;

  /// « Volume uniforme » : ajuste le volume de chaque morceau pour que
  /// tous sonnent à peu près aussi fort.
  final bool normalizeVolume;

  const EqualizerSettings({
    this.enabled = false,
    this.preset = 'Neutre',
    this.gains = const [],
    this.loudnessDb = 0,
    this.normalizeVolume = false,
  });

  EqualizerSettings copyWith({
    bool? enabled,
    String? preset,
    List<double>? gains,
    double? loudnessDb,
    bool? normalizeVolume,
  }) =>
      EqualizerSettings(
        enabled: enabled ?? this.enabled,
        preset: preset ?? this.preset,
        gains: gains ?? this.gains,
        loudnessDb: loudnessDb ?? this.loudnessDb,
        normalizeVolume: normalizeVolume ?? this.normalizeVolume,
      );

  /// Interpolation linéaire de [source] sur [count] points.
  static List<double> resample(List<double> source, int count) {
    if (count <= 0) return const [];
    if (source.isEmpty) return List<double>.filled(count, 0);
    if (source.length == count) return List<double>.from(source);
    if (source.length == 1) return List<double>.filled(count, source.first);
    if (count == 1) return [source.reduce((a, b) => a + b) / source.length];
    return [
      for (var i = 0; i < count; i++)
        () {
          final pos = i * (source.length - 1) / (count - 1);
          final lo = pos.floor();
          final hi = pos.ceil();
          final t = pos - lo;
          return source[lo] * (1 - t) + source[hi] * t;
        }(),
    ];
  }

  static EqualizerPreset? presetByName(String name) {
    for (final p in presets) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Gains (dB) à appliquer pour [bandCount] bandes.
  List<double> gainsFor(int bandCount) {
    final p = presetByName(preset);
    final source = p != null ? p.curve : gains;
    return resample(source, bandCount);
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'preset': preset,
        'gains': gains,
        'loudnessDb': loudnessDb,
        'normalizeVolume': normalizeVolume,
      };

  factory EqualizerSettings.fromJson(Map<String, dynamic> j) =>
      EqualizerSettings(
        enabled: j['enabled'] as bool? ?? false,
        preset: j['preset'] as String? ?? 'Neutre',
        gains: [
          for (final g in (j['gains'] as List<dynamic>? ?? const []))
            (g as num).toDouble(),
        ],
        loudnessDb: ((j['loudnessDb'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, maxLoudnessDb)
            .toDouble(),
        normalizeVolume: j['normalizeVolume'] as bool? ?? false,
      );
}
