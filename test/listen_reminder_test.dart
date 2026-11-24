import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/listen_event.dart';

void main() {
  final event = ListenEvent(
    id: 1,
    trackId: 1,
    title: 'Titre',
    artist: 'Artiste',
    at: DateTime(2026, 1, 10, 15, 30),
  );

  test('« hier » se tait pendant la lecture', () {
    expect(ListenReminder(event, ReminderKind.nextDay).skipsWhilePlaying, isTrue);
  });

  test('semaine, mois, six mois et un an restent envoyés', () {
    for (final k in [
      ReminderKind.nextWeek,
      ReminderKind.nextMonth,
      ReminderKind.sixMonths,
      ReminderKind.oneYear,
    ]) {
      expect(ListenReminder(event, k).skipsWhilePlaying, isFalse);
    }
  });

  test('plus de rappel à l\'heure : cinq échéances, toutes à la même heure', () {
    expect(ReminderKind.values.length, 5);
    for (final k in ReminderKind.values) {
      final at = ListenReminder(event, k).scheduledAt;
      expect([at.hour, at.minute], [15, 30]);
      expect(at.isAfter(event.at.add(const Duration(hours: 23))), isTrue);
    }
  });

  test('six mois et un an tombent le même jour du mois', () {
    expect(ListenReminder(event, ReminderKind.sixMonths).scheduledAt,
        DateTime(2026, 7, 10, 15, 30));
    expect(ListenReminder(event, ReminderKind.oneYear).scheduledAt,
        DateTime(2027, 1, 10, 15, 30));
  });

  test('fin de mois : ramené au dernier jour du mois cible', () {
    final e = ListenEvent(
        id: 3, trackId: 3, title: 'T', artist: 'A', at: DateTime(2026, 8, 31, 9, 0));
    expect(ListenReminder(e, ReminderKind.sixMonths).scheduledAt,
        DateTime(2027, 2, 28, 9, 0));
    final leap = ListenEvent(
        id: 4, trackId: 4, title: 'T', artist: 'A', at: DateTime(2024, 2, 29, 9, 0));
    expect(ListenReminder(leap, ReminderKind.oneYear).scheduledAt,
        DateTime(2025, 2, 28, 9, 0));
  });

  test('la pochette survit à la sérialisation, et son absence est tolérée', () {
    final withCover = ListenEvent(
      id: 2,
      trackId: 2,
      title: 'T',
      artist: 'A',
      at: DateTime(2026, 1, 10, 15, 30),
      cover: '/cache/art_2.jpg',
    );
    expect(ListenEvent.fromJson(withCover.toJson()).cover, '/cache/art_2.jpg');

    final old = Map<String, dynamic>.from(event.toJson())..remove('cover');
    expect(ListenEvent.fromJson(old).cover, isNull);
  });
}
