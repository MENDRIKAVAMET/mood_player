import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/listen_event.dart';
import '../models/track.dart';

/// Notifications programmées pour les rappels « à la même heure ». Elles
/// servent quand l'app n'est pas ouverte ; quand elle l'est, c'est un
/// pop-up qui prend le relais (voir `ListenReminderHost`).
class ReminderNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'mood_player_reminders',
    'Rappels d\'écoute',
    channelDescription:
        'Te rappelle ce que tu écoutais la veille ou la semaine dernière à la même heure',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );
    _initialized = true;
  }

  /// Android 13+ : demande l'autorisation d'afficher des notifications
  /// (sans effet si elle est déjà accordée ou sur les versions plus
  /// anciennes).
  static Future<void> requestPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> schedule(ListenReminder reminder) async {
    await init();
    // Instant absolu exprimé en UTC : le fuseau local n'a pas besoin
    // d'être configuré pour une notification ponctuelle.
    final when = tz.TZDateTime.from(reminder.scheduledAt, tz.UTC);
    if (when.isBefore(tz.TZDateTime.now(tz.UTC))) return;

    final e = reminder.event;
    final ago = reminder.kind == ReminderKind.nextDay
        ? 'Hier à cette heure'
        : 'Il y a une semaine à cette heure';
    final mood = e.moodType;
    final moodText = mood == null ? '' : ' (${mood.displayName})';

    await _plugin.zonedSchedule(
      reminder.notificationId,
      'Ça te dit de réécouter ?',
      '$ago, tu écoutais « ${e.title} » de ${e.artist}$moodText',
      when,
      const NotificationDetails(android: _androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancel(int notificationId) async {
    await init();
    await _plugin.cancel(notificationId);
  }
}
