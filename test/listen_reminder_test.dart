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

  test('« il y a une heure » et « hier » se taisent pendant la lecture', () {
    expect(ListenReminder(event, ReminderKind.oneHour).skipsWhilePlaying, isTrue);
    expect(ListenReminder(event, ReminderKind.nextDay).skipsWhilePlaying, isTrue);
  });

  test('la semaine et le mois dernier restent envoyés', () {
    expect(ListenReminder(event, ReminderKind.nextWeek).skipsWhilePlaying, isFalse);
    expect(ListenReminder(event, ReminderKind.nextMonth).skipsWhilePlaying, isFalse);
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
