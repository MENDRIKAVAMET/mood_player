import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
        'Te rappelle ce que tu écoutais il y a une heure, hier, la semaine ou le mois dernier',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_notification'),
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
    final ago = reminder.notificationLead;
    final mood = e.moodType;
    final moodText = mood == null ? '' : ' (${mood.displayName})';

    final title = 'Ça te dit de réécouter ?';
    final body = '$ago, tu écoutais « ${e.title} » de ${e.artist}$moodText';

    // Alarme exacte qui passe aussi le mode Doze (écran éteint, téléphone
    // immobile) : c'est ce qui fait arriver la notification à l'heure même
    // quand l'app est fermée. Si Android refuse l'alarme exacte, on retombe
    // sur une alarme approximative plutôt que de ne rien programmer.
    for (final mode in [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]) {
      try {
        await _plugin.zonedSchedule(
          reminder.notificationId,
          title,
          body,
          when,
          const NotificationDetails(android: _androidDetails),
          androidScheduleMode: mode,
        );
        return;
      } catch (err) {
        debugPrint('ReminderNotificationService: schedule ($mode) failed: $err');
      }
    }
  }

  /// Sur beaucoup de téléphones (Xiaomi, Tecno, Infinix, Huawei, Samsung…),
  /// l'optimisation de batterie supprime les alarmes d'une app retirée des
  /// applications récentes. Demande UNE fois d'exclure l'app de cette
  /// optimisation (une boîte de dialogue système).
  static Future<void> askBatteryExemptionOnce() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final marker = File('${dir.path}/battery_exemption_asked');
      if (await marker.exists()) return;
      if (await Permission.ignoreBatteryOptimizations.isGranted) return;
      await marker.writeAsString('1');
      await Permission.ignoreBatteryOptimizations.request();
    } catch (err) {
      debugPrint('ReminderNotificationService: battery exemption: $err');
    }
  }

  static Future<void> cancel(int notificationId) async {
    await init();
    await _plugin.cancel(notificationId);
  }
}
