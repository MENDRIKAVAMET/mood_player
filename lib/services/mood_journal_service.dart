import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import '../models/mood_journal_entry.dart';
import '../models/play_log_entry.dart';
import '../models/track.dart';
import 'mood_query_parser.dart';

/// Persistance du journal d'humeur : simple fichier JSON, comme le journal
/// d'écoute (pas de schéma Isar, donc pas de migration). Reste sur
/// l'appareil.
class MoodJournalService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/mood_journal.json');
  }

  Future<List<MoodJournalEntry>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final out = <MoodJournalEntry>[];
      for (final raw in json['entries'] as List<dynamic>? ?? const []) {
        try {
          final e = MoodJournalEntry.tryFromJson(
              Map<String, dynamic>.from(raw as Map));
          if (e != null) out.add(e);
        } catch (_) {
          // Une ligne abîmée ne doit pas faire perdre tout le journal.
        }
      }
      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<MoodJournalEntry> entries) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'v': 1,
        'entries': entries.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {
      // L'état en mémoire reste valable pour la session.
    }
  }
}

/// Ce que l'utilisateur écoute quand il dit ressentir [feeling].
class FeelingInsight {
  final Feeling feeling;

  /// Nombre de fois où cette humeur a été notée.
  final int entries;

  /// Nombre d'écoutes classées par ambiance, dans la fenêtre qui suit chaque
  /// note.
  final int listens;

  /// Ambiances les plus écoutées (au plus 3), avec leur part (0 à 1).
  final List<MapEntry<MoodType, double>> topMoods;

  const FeelingInsight({
    required this.feeling,
    required this.entries,
    required this.listens,
    required this.topMoods,
  });

  /// Assez d'écoutes pour que le constat ait un sens.
  bool get reliable => listens >= MoodJournalInsights.minListens;
}

/// Croise le journal d'humeur et le journal d'écoute : pour chaque humeur
/// notée, quelles ambiances ont été écoutées dans les heures qui suivent.
/// C'est un constat (« tu écoutes surtout »), pas une preuve que cette
/// musique aide.
class MoodJournalInsights {
  MoodJournalInsights._();

  /// Une écoute compte pour une humeur si elle a lieu moins de 3 h après la
  /// note, et avant la note suivante.
  static const Duration listenWindow = Duration(hours: 3);

  /// Écoutes minimum avant de considérer un constat comme fiable.
  static const int minListens = 5;

  static List<FeelingInsight> compute(
    List<MoodJournalEntry> journal,
    List<PlayLogEntry> log,
  ) {
    if (journal.isEmpty) return const [];
    final entries = [...journal]..sort((a, b) => a.at.compareTo(b.at));
    final plays = [...log]..sort((a, b) => a.at.compareTo(b.at));

    final entryCount = <Feeling, int>{};
    final moodCounts = <Feeling, Map<MoodType, int>>{};

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      entryCount[e.feeling] = (entryCount[e.feeling] ?? 0) + 1;

      var end = e.at.add(listenWindow);
      if (i + 1 < entries.length && entries[i + 1].at.isBefore(end)) {
        end = entries[i + 1].at;
      }

      for (var j = _lowerBound(plays, e.at); j < plays.length; j++) {
        final p = plays[j];
        if (!p.at.isBefore(end)) break;
        final m = p.moodType;
        if (m == null || m == MoodType.unknown) continue;
        final bucket = moodCounts.putIfAbsent(e.feeling, () => {});
        bucket[m] = (bucket[m] ?? 0) + 1;
      }
    }

    final result = <FeelingInsight>[];
    for (final f in entryCount.keys) {
      final counts = moodCounts[f] ?? const <MoodType, int>{};
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      result.add(FeelingInsight(
        feeling: f,
        entries: entryCount[f]!,
        listens: total,
        topMoods: [
          for (final e in sorted.take(3)) MapEntry(e.key, e.value / total),
        ],
      ));
    }
    result.sort((a, b) => b.entries.compareTo(a.entries));
    return result;
  }

  /// Première écoute dont la date est >= [at] ([plays] trié).
  static int _lowerBound(List<PlayLogEntry> plays, DateTime at) {
    var lo = 0;
    var hi = plays.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (plays[mid].at.isBefore(at)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static FeelingInsight? insightFor(
    Feeling feeling,
    List<FeelingInsight> insights,
  ) {
    for (final i in insights) {
      if (i.feeling == feeling) return i;
    }
    return null;
  }

  /// Ambiances à proposer pour [feeling] : celles que l'utilisateur écoute
  /// vraiment dans cet état si on a assez de recul, sinon les ambiances par
  /// défaut de l'humeur.
  static List<MoodType> moodsFor(
    Feeling feeling,
    List<FeelingInsight> insights,
  ) {
    final i = insightFor(feeling, insights);
    if (i == null || !i.reliable) return feeling.defaultMoods;
    final picked = [
      for (final e in i.topMoods)
        if (e.value >= 0.2) e.key,
    ].take(2).toList();
    return picked.isEmpty ? feeling.defaultMoods : picked;
  }

  /// Mix de [size] morceaux pour ces ambiances : tirés au hasard parmi les
  /// plus pertinents, pour que deux mix successifs ne soient pas identiques.
  static List<Track> mixFor(
    List<Track> library,
    List<MoodType> moods, {
    int size = 20,
    math.Random? random,
  }) {
    if (moods.isEmpty) return const [];
    final weights = <MoodType, double>{
      for (var i = 0; i < moods.length; i++) moods[i]: i == 0 ? 1.0 : 0.7,
    };
    final ranked = MoodQuery(weights: weights).rank(library);
    final pool = ranked.take(size * 3).toList()
      ..shuffle(random ?? math.Random());
    return pool.take(size).toList();
  }
}
