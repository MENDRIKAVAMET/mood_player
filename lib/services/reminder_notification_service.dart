import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/listen_event.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';

/// Notifications programmées pour les rappels « à la même heure ». Elles
/// servent quand l'app n'est pas ouverte ; quand elle l'est, c'est un
/// pop-up qui prend le relais (voir `ListenReminderHost`).
class ReminderNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _channelId = 'mood_player_reminders';
  static const String _actionPlay = 'play_track';

  /// Un rappel affiché reste visible au plus 1 h : au-delà, la proposition
  /// n'a plus de sens (même fenêtre que le pop-up dans l'app).
  static const int _timeoutMs = 60 * 60 * 1000;

  /// Id du morceau touché dans une notification (ou via « Écouter »).
  /// Écouté par `ListenReminderHost`, qui ouvre alors le lecteur.
  static final StreamController<int> _taps = StreamController<int>.broadcast();
  static Stream<int> get taps => _taps.stream;

  /// Tap reçu AVANT que l'interface soit prête (app lancée par la
  /// notification) : conservé ici jusqu'à ce que le host le récupère.
  static int? _pendingTapTrackId;

  static int? takePendingTap() {
    final id = _pendingTapTrackId;
    _pendingTapTrackId = null;
    return id;
  }

  static void _onResponse(NotificationResponse response) {
    final id = int.tryParse(response.payload ?? '');
    if (id == null) return;
    if (_taps.hasListener) {
      _taps.add(id);
    } else {
      _pendingTapTrackId = id;
    }
  }

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_notification'),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    _initialized = true;

    // App lancée (démarrage à froid) en touchant une notification.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final r = launch!.notificationResponse;
        if (r != null) _onResponse(r);
      }
    } catch (err) {
      debugPrint('ReminderNotificationService: launch details: $err');
    }
  }

  /// Notification soignée : pochette du morceau en grande icône, couleur de
  /// l'app, titre + texte enrichi (titre en gras, artiste, ambiance) et un
  /// bouton « Écouter ».
  static AndroidNotificationDetails _buildDetails(ListenReminder reminder) {
    final e = reminder.event;
    final mood = e.moodType;
    final moodLine = (mood == null || mood == MoodType.unknown)
        ? ''
        : '<br/>${mood.icon} ${_esc(mood.displayName)}';

    final cover = e.cover;
    final hasCover = cover != null && cover.isNotEmpty && File(cover).existsSync();

    return AndroidNotificationDetails(
      _channelId,
      'Rappels d\'écoute',
      channelDescription:
          'Te rappelle ce que tu écoutais il y a une heure, hier, la semaine ou le mois dernier',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.recommendation,
      color: AppTheme.accentPrimary,
      largeIcon: hasCover ? FilePathAndroidBitmap(cover) : null,
      // « Aura · Hier à cette heure » dans l'en-tête de la notification.
      subText: reminder.notificationLead,
      showWhen: false,
      autoCancel: true,
      timeoutAfter: _timeoutMs,
      styleInformation: BigTextStyleInformation(
        '<b>${_esc(e.title)}</b><br/>${_esc(e.artist)}$moodLine',
        htmlFormatBigText: true,
        contentTitle: 'Ça te dit de réécouter ?',
        htmlFormatContentTitle: false,
      ),
      actions: const [
        AndroidNotificationAction(
          _actionPlay,
          'Écouter',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
  }

  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

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
    const title = 'Ça te dit de réécouter ?';
    // Texte replié : une ligne lisible ; le détail est dans le style étendu.
    final body = '« ${e.title} » · ${e.artist}';

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
          NotificationDetails(android: _buildDetails(reminder)),
          androidScheduleMode: mode,
          payload: '${e.trackId}',
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
