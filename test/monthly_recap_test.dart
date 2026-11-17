import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/play_log_entry.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/providers/play_log_provider.dart';
import 'package:mood_player/services/recap_builder.dart';

PlayLogEntry _e(int id, String title, DateTime at, {MoodType? mood}) =>
    PlayLogEntry(
      trackId: id,
      title: title,
      artist: 'Artiste',
      mood: mood?.name,
      at: at,
    );

final _nov = DateTime(2026, 11);

DateTime _d(int day, [int hour = 12]) => DateTime(2026, 11, day, hour);

void main() {
  group('RecapBuilder.build', () {
    test('mois sans écoute → bilan vide', () {
      final r = RecapBuilder.build(const [], _nov);
      expect(r.totalPlays, 0);
      expect(r.dominantMood, isNull);
      expect(r.topTracks, isEmpty);
      expect(r.favoriteHour, isNull);
      expect(r.hasEnoughData, isFalse);
    });

    test('seuil : 4 écoutes ne suffisent pas, 5 oui', () {
      final four = [for (var i = 0; i < 4; i++) _e(i, 't$i', _d(1 + i))];
      expect(RecapBuilder.build(four, _nov).hasEnoughData, isFalse);
      final five = [...four, _e(9, 't9', _d(9))];
      expect(RecapBuilder.build(five, _nov).hasEnoughData, isTrue);
    });

    test('ne compte que le mois demandé (et la bonne année)', () {
      final entries = [
        _e(1, 'a', _d(3)),
        _e(1, 'a', DateTime(2026, 10, 31, 23)),
        _e(1, 'a', DateTime(2026, 12, 1, 0)),
        _e(1, 'a', DateTime(2025, 11, 3)),
      ];
      expect(RecapBuilder.build(entries, _nov).totalPlays, 1);
    });

    test('ambiance dominante et part parmi les écoutes classées', () {
      final entries = [
        for (var i = 0; i < 3; i++) _e(i, 'c$i', _d(1 + i), mood: MoodType.chill),
        for (var i = 0; i < 2; i++)
          _e(10 + i, 'e$i', _d(10 + i), mood: MoodType.energetic),
        // Non classés : ne comptent pas dans la part.
        _e(20, 'x', _d(20)),
        _e(21, 'y', _d(21), mood: MoodType.unknown),
      ];
      final r = RecapBuilder.build(entries, _nov);
      expect(r.dominantMood, MoodType.chill);
      expect(r.dominantShare, closeTo(3 / 5, 1e-9));
      expect(r.totalPlays, 7);
    });

    test('égalité d\'ambiances : la première de l\'énumération', () {
      final entries = [
        _e(1, 'a', _d(1), mood: MoodType.energetic),
        _e(2, 'b', _d(2), mood: MoodType.chill),
      ];
      final expected = [MoodType.energetic, MoodType.chill]
        ..sort((a, b) => a.index.compareTo(b.index));
      expect(RecapBuilder.build(entries, _nov).dominantMood, expected.first);
    });

    test('aucune écoute classée → pas d\'ambiance dominante', () {
      final entries = [for (var i = 0; i < 5; i++) _e(i, 't$i', _d(1 + i))];
      final r = RecapBuilder.build(entries, _nov);
      expect(r.dominantMood, isNull);
      expect(r.dominantShare, 0);
    });

    test('top morceaux : par écoutes, puis le plus récent, limité à 3', () {
      final entries = [
        _e(1, 'trois fois', _d(1)),
        _e(1, 'trois fois', _d(2)),
        _e(1, 'trois fois', _d(3)),
        _e(2, 'deux, ancien', _d(4)),
        _e(2, 'deux, ancien', _d(5)),
        _e(3, 'deux, récent', _d(6)),
        _e(3, 'deux, récent', _d(20)),
        _e(4, 'une fois', _d(7)),
      ];
      final top = RecapBuilder.build(entries, _nov).topTracks;
      expect(top.map((t) => t.title),
          ['trois fois', 'deux, récent', 'deux, ancien']);
      expect(top.first.plays, 3);
    });

    test('le titre affiché est celui de la dernière écoute', () {
      final entries = [
        _e(1, 'ancien titre', _d(1)),
        _e(1, 'nouveau titre', _d(9)),
      ];
      expect(RecapBuilder.build(entries, _nov).topTracks.single.title,
          'nouveau titre');
    });

    test('heure favorite, et la plus tôt à égalité', () {
      final entries = [
        for (var i = 0; i < 3; i++) _e(i, 'soir$i', _d(1 + i, 21)),
        for (var i = 0; i < 2; i++) _e(10 + i, 'matin$i', _d(10 + i, 8)),
      ];
      expect(RecapBuilder.build(entries, _nov).favoriteHour, 21);

      final tie = [_e(1, 'a', _d(1, 22)), _e(2, 'b', _d(2, 7))];
      expect(RecapBuilder.build(tie, _nov).favoriteHour, 7);
    });
  });

  group('RecapBuilder (mois et libellés)', () {
    test('monthsWithData : du plus récent au plus ancien, sans doublon', () {
      final entries = [
        _e(1, 'a', DateTime(2026, 9, 3)),
        _e(1, 'a', DateTime(2026, 11, 3)),
        _e(1, 'a', DateTime(2026, 11, 20)),
        _e(1, 'a', DateTime(2025, 12, 31)),
      ];
      expect(RecapBuilder.monthsWithData(entries), [
        DateTime(2026, 11),
        DateTime(2026, 9),
        DateTime(2025, 12),
      ]);
    });

    test('monthLabel, hourLabel, dayPeriod', () {
      expect(RecapBuilder.monthLabel(DateTime(2026, 11)), 'Novembre 2026');
      expect(RecapBuilder.monthLabel(DateTime(2026, 2)), 'Février 2026');
      expect(RecapBuilder.hourLabel(21), '21 h');
      expect(RecapBuilder.dayPeriod(8), 'le matin');
      expect(RecapBuilder.dayPeriod(12), 'le midi');
      expect(RecapBuilder.dayPeriod(16), "l'après-midi");
      expect(RecapBuilder.dayPeriod(21), 'en soirée');
      expect(RecapBuilder.dayPeriod(23), 'la nuit');
      expect(RecapBuilder.dayPeriod(3), 'la nuit');
    });
  });

  group('PlayLogEntry', () {
    test('aller-retour JSON, avec et sans ambiance', () {
      final with_ = _e(7, 'Titre', DateTime(2026, 11, 5, 21, 30),
          mood: MoodType.chill);
      final back = PlayLogEntry.fromJson(with_.toJson());
      expect(back.trackId, 7);
      expect(back.title, 'Titre');
      expect(back.moodType, MoodType.chill);
      expect(back.at, with_.at);

      final without = PlayLogEntry.fromJson(_e(8, 'x', _d(1)).toJson());
      expect(without.mood, isNull);
      expect(without.moodType, isNull);
    });

    test('ambiance inconnue du code → null, sans planter', () {
      final e = PlayLogEntry.fromJson({
        'i': 1,
        't': 'x',
        'a': 'y',
        'm': 'ambiance_supprimee',
        'at': _d(1).millisecondsSinceEpoch,
      });
      expect(e.moodType, isNull);
    });
  });

  group('PlayLogNotifier.prune', () {
    final now = DateTime(2026, 11, 17, 12);

    test('retire les écoutes de plus de 400 jours', () {
      final old = _e(1, 'vieux', now.subtract(const Duration(days: 401)));
      final recent = _e(2, 'récent', now.subtract(const Duration(days: 399)));
      expect(PlayLogNotifier.prune([old, recent], now).map((e) => e.title),
          ['récent']);
    });

    test('plafonne à maxEntries en gardant les plus récentes', () {
      final entries = [
        for (var i = 0; i < PlayLogNotifier.maxEntries + 5; i++)
          _e(i, 't$i', now.subtract(Duration(minutes: 1)).add(Duration(milliseconds: i))),
      ];
      final kept = PlayLogNotifier.prune(entries, now);
      expect(kept.length, PlayLogNotifier.maxEntries);
      expect(kept.first.trackId, 5);
      expect(kept.last.trackId, PlayLogNotifier.maxEntries + 4);
    });
  });
}
