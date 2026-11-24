import 'track.dart';

/// Une écoute « réelle » (≥ 80 % du morceau) datée, pour le bilan du mois.
///
/// Contrairement à [ListenEvent] (une seule écoute par ouverture de l'app,
/// jetée après environ un an, pour les rappels) et aux compteurs d'écoute (un
/// total sans date), le journal garde CHAQUE écoute avec son horodatage :
/// c'est ce qui permet de dire « ce mois-ci » et « ton heure favorite ».
///
/// Le titre et l'artiste sont copiés : le bilan reste lisible même si le
/// morceau est supprimé de la bibliothèque ensuite.
class PlayLogEntry {
  final int trackId;
  final String title;
  final String artist;

  /// Nom de [MoodType] au moment de l'écoute, null si le morceau n'était
  /// pas classé.
  final String? mood;

  /// Heure locale de l'écoute.
  final DateTime at;

  const PlayLogEntry({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.at,
    this.mood,
  });

  MoodType? get moodType {
    final m = mood;
    if (m == null) return null;
    for (final t in MoodType.values) {
      if (t.name == m) return t;
    }
    return null;
  }

  // Clés courtes : le fichier peut contenir plusieurs milliers d'écoutes.
  Map<String, dynamic> toJson() => {
        'i': trackId,
        't': title,
        'a': artist,
        'm': mood,
        'at': at.millisecondsSinceEpoch,
      };

  factory PlayLogEntry.fromJson(Map<String, dynamic> json) => PlayLogEntry(
        trackId: (json['i'] as num).toInt(),
        title: json['t'] as String? ?? '',
        artist: json['a'] as String? ?? '',
        mood: json['m'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
      );
}
