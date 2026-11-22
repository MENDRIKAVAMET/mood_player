import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/mood_journal_entry.dart';
import 'package:mood_player/models/play_log_entry.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/mood_journal_service.dart';

PlayLogEntry _play(DateTime at, MoodType? mood, {int id = 1}) => PlayLogEntry(
      trackId: id,
      title: 'T$id',
      artist: 'A',
      mood: mood?.name,
      at: at,
    );

void main() {
  final t0 = DateTime(2026, 11, 20, 20, 0);

  test('entrée : aller-retour JSON et ligne abîmée', () {
    final e = MoodJournalEntry(at: t0, feeling: Feeling.stressed, note: 'exam');
    expect(MoodJournalEntry.tryFromJson(e.toJson()), e);
    expect(MoodJournalEntry.tryFromJson({'f': 'inconnu', 'at': 1}), isNull);
    expect(MoodJournalEntry.tryFromJson({'f': 'sad'}), isNull);
  });

  test('constat : écoutes dans les 3 h qui suivent la note', () {
    final journal = [MoodJournalEntry(at: t0, feeling: Feeling.stressed)];
    final log = [
      _play(t0.subtract(const Duration(minutes: 5)), MoodType.energetic),
      _play(t0.add(const Duration(minutes: 10)), MoodType.chill),
      _play(t0.add(const Duration(minutes: 20)), MoodType.chill),
      _play(t0.add(const Duration(minutes: 30)), MoodType.classical),
      _play(t0.add(const Duration(hours: 4)), MoodType.energetic),
      _play(t0.add(const Duration(minutes: 40)), null),
    ];
    final i = MoodJournalInsights.compute(journal, log).single;
    expect(i.entries, 1);
    expect(i.listens, 3);
    expect(i.topMoods.first.key, MoodType.chill);
    expect(i.topMoods.first.value, closeTo(2 / 3, 0.001));
    expect(i.reliable, false);
  });

  test('la fenêtre s\'arrête à la note suivante', () {
    final journal = [
      MoodJournalEntry(at: t0, feeling: Feeling.sad),
      MoodJournalEntry(
          at: t0.add(const Duration(minutes: 30)), feeling: Feeling.joyful),
    ];
    final log = [
      _play(t0.add(const Duration(minutes: 10)), MoodType.sad),
      _play(t0.add(const Duration(minutes: 40)), MoodType.festive),
    ];
    final insights = MoodJournalInsights.compute(journal, log);
    expect(
      MoodJournalInsights.insightFor(Feeling.sad, insights)!.topMoods.single.key,
      MoodType.sad,
    );
    expect(
      MoodJournalInsights.insightFor(Feeling.joyful, insights)!
          .topMoods
          .single
          .key,
      MoodType.festive,
    );
  });

  test('ambiances proposées : défaut sans recul, habitudes avec recul', () {
    expect(MoodJournalInsights.moodsFor(Feeling.stressed, const []),
        Feeling.stressed.defaultMoods);

    final journal = [
      for (var d = 0; d < 3; d++)
        MoodJournalEntry(
          at: t0.add(Duration(days: d)),
          feeling: Feeling.stressed,
        ),
    ];
    final log = [
      for (var d = 0; d < 3; d++) ...[
        _play(t0.add(Duration(days: d, minutes: 5)), MoodType.melancholic),
        _play(t0.add(Duration(days: d, minutes: 10)), MoodType.melancholic),
      ],
    ];
    final insights = MoodJournalInsights.compute(journal, log);
    expect(insights.single.reliable, true);
    expect(MoodJournalInsights.moodsFor(Feeling.stressed, insights),
        [MoodType.melancholic]);
  });

  test('mix : seulement des morceaux de l\'ambiance, taille respectée', () {
    final library = [
      for (var i = 1; i <= 50; i++)
        Track()
          ..id = i
          ..title = 'T$i'
          ..artist = 'A'
          ..mood = i <= 30 ? MoodType.chill : MoodType.energetic,
    ];
    final mix = MoodJournalInsights.mixFor(
      library,
      [MoodType.chill],
      random: Random(3),
    );
    expect(mix.length, 20);
    expect(mix.every((t) => t.mood == MoodType.chill), true);
    expect(MoodJournalInsights.mixFor(library, const []), isEmpty);
  });
}
