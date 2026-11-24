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

  /// Chemin LOCAL de la pochette (cache d'artwork), pour l'afficher dans la
  /// notification système. Null si le morceau n'en a pas (ou si la pochette
  /// est une URL distante, qu'Android ne peut pas charger à l'heure du rappel).
  final String? cover;

  const ListenEvent({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.at,
    this.mood,
    this.cover,
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
        'cover': cover,
        'at': at.toIso8601String(),
      };

  factory ListenEvent.fromJson(Map<String, dynamic> json) => ListenEvent(
        id: (json['id'] as num).toInt(),
        trackId: (json['trackId'] as num).toInt(),
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        mood: json['mood'] as String?,
        cover: json['cover'] as String?,
        at: DateTime.parse(json['at'] as String).toLocal(),
      );
}

/// Moment du rappel : un jour, une semaine, un mois, six mois ou un an après
/// l'écoute, toujours à la même heure. Plus aucun rappel à l'heure : un
/// rappel « il y a une heure » n'avait pas de sens, l'écoute est trop fraîche.
enum ReminderKind { nextDay, nextWeek, nextMonth, sixMonths, oneYear }

class ListenReminder {
  final ListenEvent event;
  final ReminderKind kind;

  const ListenReminder(this.event, this.kind);

  /// Identifiant de notification propre à chaque type, FIXE : il ne dépend
  /// pas de l'ordre de l'enum, pour que les notifications déjà programmées
  /// par une ancienne version soient remplacées et non dupliquées.
  /// (2 était l'ancien rappel « il y a une heure », voir
  /// [legacyOneHourNotificationId].)
  int get _kindCode {
    switch (kind) {
      case ReminderKind.nextDay:
        return 0;
      case ReminderKind.nextWeek:
        return 1;
      case ReminderKind.nextMonth:
        return 3;
      case ReminderKind.sixMonths:
        return 4;
      case ReminderKind.oneYear:
        return 5;
    }
  }

  /// Même jour du mois, [months] mois plus tard, ramené au dernier jour du
  /// mois si celui-ci est plus court (31 août + 6 mois → 28/29 février).
  static DateTime _addMonths(DateTime a, int months) {
    final total = a.month - 1 + months;
    final year = a.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
        year, month, a.day > lastDay ? lastDay : a.day, a.hour, a.minute);
  }

  /// Même heure et même minute, plus tard. Construit champ par champ (et
  /// non avec `+ Duration(days:)`) pour rester à la même heure locale
  /// malgré un changement d'heure été/hiver.
  DateTime get scheduledAt {
    final a = event.at;
    switch (kind) {
      case ReminderKind.nextDay:
        return DateTime(a.year, a.month, a.day + 1, a.hour, a.minute);
      case ReminderKind.nextWeek:
        return DateTime(a.year, a.month, a.day + 7, a.hour, a.minute);
      case ReminderKind.nextMonth:
        return DateTime(a.year, a.month, a.day + 30, a.hour, a.minute);
      case ReminderKind.sixMonths:
        return _addMonths(a, 6);
      case ReminderKind.oneYear:
        return _addMonths(a, 12);
    }
  }

  String get key => '${event.id}:${kind.name}';

  /// Le rappel « hier » ne doit pas être envoyé pendant que l'utilisateur
  /// écoute de la musique : il est déjà en train d'écouter, et c'est une
  /// écoute trop récente pour qu'un rappel ait du sens. Les autres, plus
  /// nostalgiques, restent envoyés.
  bool get skipsWhilePlaying => kind == ReminderKind.nextDay;

  /// Un seul identifiant de notification par créneau horaire : plusieurs
  /// écoutes dans la même heure n'envoient jamais plusieurs notifications.
  int get notificationId {
    final s = scheduledAt;
    return Object.hash(s.year, s.month, s.day, s.hour, _kindCode) & 0x3FFFFFFF;
  }

  /// Identifiant qu'avait la notification « il y a une heure » des versions
  /// précédentes : sert à annuler celles qui sont encore programmées dans
  /// le système après la mise à jour.
  static int legacyOneHourNotificationId(ListenEvent event) {
    final a = event.at;
    final s = DateTime(a.year, a.month, a.day, a.hour + 1, a.minute);
    return Object.hash(s.year, s.month, s.day, s.hour, 2) & 0x3FFFFFFF;
  }

  String get whenLabel {
    final a = event.at;
    final hh = a.hour.toString().padLeft(2, '0');
    final mm = a.minute.toString().padLeft(2, '0');
    switch (kind) {
      case ReminderKind.nextDay:
        return 'Hier à $hh:$mm';
      case ReminderKind.nextWeek:
        return 'Il y a une semaine à $hh:$mm';
      case ReminderKind.nextMonth:
        return 'Il y a un mois à $hh:$mm';
      case ReminderKind.sixMonths:
        return 'Il y a six mois à $hh:$mm';
      case ReminderKind.oneYear:
        return 'Il y a un an à $hh:$mm';
    }
  }

  /// Début de phrase de la notification (« … , tu écoutais « titre » »).
  String get notificationLead {
    switch (kind) {
      case ReminderKind.nextDay:
        return 'Hier à cette heure';
      case ReminderKind.nextWeek:
        return 'Il y a une semaine à cette heure';
      case ReminderKind.nextMonth:
        return 'Il y a un mois à cette heure';
      case ReminderKind.sixMonths:
        return 'Il y a six mois à cette heure';
      case ReminderKind.oneYear:
        return 'Il y a un an à cette heure';
    }
  }
}
