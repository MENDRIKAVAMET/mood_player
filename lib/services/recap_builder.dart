import '../models/play_log_entry.dart';
import '../models/track.dart';

/// Un morceau du top du mois.
class RecapTrack {
  final int trackId;
  final String title;
  final String artist;
  final int plays;

  const RecapTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.plays,
  });
}

/// Le bilan d'un mois d'écoute, prêt à être mis en carte.
class MonthlyRecap {
  /// En dessous, le bilan serait trop maigre pour être partagé.
  static const int minPlays = 5;

  /// Premier jour du mois (heure locale).
  final DateTime month;
  final int totalPlays;

  /// Ambiance la plus écoutée parmi les morceaux classés, null si aucun
  /// morceau écouté n'était classé.
  final MoodType? dominantMood;

  /// Part de [dominantMood] parmi les écoutes classées, entre 0 et 1.
  final double dominantShare;
  final List<RecapTrack> topTracks;

  /// Heure (0 à 23) où l'on écoute le plus, null si aucune écoute.
  final int? favoriteHour;

  const MonthlyRecap({
    required this.month,
    this.totalPlays = 0,
    this.dominantMood,
    this.dominantShare = 0,
    this.topTracks = const [],
    this.favoriteHour,
  });

  bool get hasEnoughData => totalPlays >= minPlays;
}

class _TrackAcc {
  final int trackId;
  String title;
  String artist;
  DateTime last;
  int plays = 0;

  _TrackAcc(this.trackId, this.title, this.artist, this.last);
}

/// Calcule le bilan d'un mois à partir du journal d'écoute. Pur et sans
/// effet de bord : tout le calcul est testable sans Flutter ni disque.
class RecapBuilder {
  RecapBuilder._();

  static const List<String> _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  static MonthlyRecap build(
    Iterable<PlayLogEntry> entries,
    DateTime month, {
    int topCount = 3,
  }) {
    final start = DateTime(month.year, month.month);
    final moodCounts = <MoodType, int>{};
    final tracks = <int, _TrackAcc>{};
    final hours = List<int>.filled(24, 0);
    var total = 0;

    for (final e in entries) {
      if (e.at.year != start.year || e.at.month != start.month) continue;
      total++;
      hours[e.at.hour]++;

      final m = e.moodType;
      if (m != null && m != MoodType.unknown) {
        moodCounts[m] = (moodCounts[m] ?? 0) + 1;
      }

      final acc = tracks.putIfAbsent(
        e.trackId,
        () => _TrackAcc(e.trackId, e.title, e.artist, e.at),
      );
      acc.plays++;
      // Le titre affiché est celui de la dernière écoute (renommage).
      if (e.at.isAfter(acc.last)) {
        acc.last = e.at;
        acc.title = e.title;
        acc.artist = e.artist;
      }
    }

    if (total == 0) return MonthlyRecap(month: start);

    // Ambiance dominante : à égalité, la première de l'énumération, pour un
    // résultat stable d'un affichage à l'autre.
    MoodType? dominant;
    var best = 0;
    var classified = 0;
    for (final m in MoodType.values) {
      final c = moodCounts[m] ?? 0;
      classified += c;
      if (c > best) {
        best = c;
        dominant = m;
      }
    }

    final ranked = tracks.values.toList()
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        if (byPlays != 0) return byPlays;
        final byRecent = b.last.compareTo(a.last);
        if (byRecent != 0) return byRecent;
        return a.title.compareTo(b.title);
      });

    // Heure favorite : à égalité, la plus tôt dans la journée.
    var bestHour = 0;
    for (var h = 1; h < 24; h++) {
      if (hours[h] > hours[bestHour]) bestHour = h;
    }

    return MonthlyRecap(
      month: start,
      totalPlays: total,
      dominantMood: dominant,
      dominantShare: classified == 0 ? 0 : best / classified,
      topTracks: [
        for (final t in ranked.take(topCount))
          RecapTrack(
            trackId: t.trackId,
            title: t.title,
            artist: t.artist,
            plays: t.plays,
          ),
      ],
      favoriteHour: bestHour,
    );
  }

  /// Mois ayant au moins une écoute, du plus récent au plus ancien.
  static List<DateTime> monthsWithData(Iterable<PlayLogEntry> entries) {
    final keys = <int>{
      for (final e in entries) e.at.year * 12 + (e.at.month - 1),
    };
    final sorted = keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in sorted) DateTime(k ~/ 12, k % 12 + 1)];
  }

  /// « Novembre 2026 ».
  static String monthLabel(DateTime month) {
    final name = _months[month.month - 1];
    return '${name[0].toUpperCase()}${name.substring(1)} ${month.year}';
  }

  /// « 21 h ».
  static String hourLabel(int hour) => '$hour h';

  /// Moment de la journée correspondant à [hour].
  static String dayPeriod(int hour) {
    if (hour >= 5 && hour <= 11) return 'le matin';
    if (hour >= 12 && hour <= 13) return 'le midi';
    if (hour >= 14 && hour <= 17) return "l'après-midi";
    if (hour >= 18 && hour <= 21) return 'en soirée';
    return 'la nuit';
  }
}
