import 'track.dart';

/// Une écoute mémorisée pour les rappels « à la même heure » : le morceau,
/// son ambiance et le moment exact où il a été écouté (heure locale).
class ListenEvent {
  final int id;
  final int trackId;
  final String title;
  final String artist;

  /// Nom de [MoodType] (`chill`, `motivating`...), null si le morceau
  /// n'était pas classé.
  final String? mood;
  final DateTime at;

  const ListenEvent({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.at,
    this.mood,
  });

  MoodType? get moodType {
    if (mood == null) return null;
    for (final m in MoodType.values) {
      if (m.name == mood) return m;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'mood': mood,
        'at': at.toIso8601String(),
      };

  factory ListenEvent.fromJson(Map<String, dynamic> json) => ListenEvent(
        id: (json['id'] as num).toInt(),
        trackId: (json['trackId'] as num).toInt(),
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        mood: json['mood'] as String?,
        at: DateTime.parse(json['at'] as String).toLocal(),
      );
}

/// Moment du rappel : une heure, un jour, une semaine ou un mois après
/// l'écoute (les trois derniers à la même heure). Les nouvelles valeurs
/// sont ajoutées à la fin pour ne pas décaler les existantes.
enum ReminderKind { nextDay, nextWeek, oneHour, nextMonth }

class ListenReminder {
  final ListenEvent event;
  final ReminderKind kind;

  const ListenReminder(this.event, this.kind);

  int get _daysLater {
    switch (kind) {
      case ReminderKind.nextDay:
        return 1;
      case ReminderKind.nextWeek:
        return 7;
      case ReminderKind.nextMonth:
        return 30;
      case ReminderKind.oneHour:
        return 0;
    }
  }

  int get _hoursLater => kind == ReminderKind.oneHour ? 1 : 0;

  /// Même heure et même minute, [_daysLater] jours plus tard. Construit
  /// champ par champ (et non avec `+ Duration(days:)`) pour rester à la
  /// même heure locale malgré un changement d'heure été/hiver.
  DateTime get scheduledAt {
    final a = event.at;
    return DateTime(
        a.year, a.month, a.day + _daysLater, a.hour + _hoursLater, a.minute);
  }

  String get key => '${event.id}:${kind.name}';

  /// Un seul identifiant de notification par créneau horaire : plusieurs
  /// écoutes dans la même heure n'envoient jamais plusieurs notifications.
  int get notificationId {
    final s = scheduledAt;
    return Object.hash(s.year, s.month, s.day, s.hour, kind.index) & 0x3FFFFFFF;
  }

  String get whenLabel {
    final a = event.at;
    final hh = a.hour.toString().padLeft(2, '0');
    final mm = a.minute.toString().padLeft(2, '0');
    switch (kind) {
      case ReminderKind.oneHour:
        return 'Il y a une heure';
      case ReminderKind.nextDay:
        return 'Hier à $hh:$mm';
      case ReminderKind.nextWeek:
        return 'Il y a une semaine à $hh:$mm';
      case ReminderKind.nextMonth:
        return 'Il y a un mois à $hh:$mm';
    }
  }

  /// Début de phrase de la notification (« … , tu écoutais « titre » »).
  String get notificationLead {
    switch (kind) {
      case ReminderKind.oneHour:
        return 'Il y a une heure';
      case ReminderKind.nextDay:
        return 'Hier à cette heure';
      case ReminderKind.nextWeek:
        return 'Il y a une semaine à cette heure';
      case ReminderKind.nextMonth:
        return 'Il y a un mois à cette heure';
    }
  }
}
