import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listen_event.dart';
import '../models/track.dart';
import '../providers/listen_history_provider.dart';
import '../providers/providers.dart';
import '../services/reminder_notification_service.dart';
import '../features/reminder/listen_reminder_screen.dart';
import '../utils/playback_navigation.dart';

/// Widget invisible qui affiche le rappel « tu écoutais ça à cette heure »
/// quand l'app est ouverte. Quand elle ne l'est pas, c'est la notification
/// programmée qui s'en charge ; ici on annule cette notification juste
/// avant l'heure pour ne pas avoir les deux en même temps.
///
/// Gère aussi le tap sur une notification (ou son bouton « Écouter ») :
/// ouvre directement le lecteur sur le morceau concerné.
class ListenReminderHost extends ConsumerStatefulWidget {
  const ListenReminderHost({super.key});

  @override
  ConsumerState<ListenReminderHost> createState() => _ListenReminderHostState();
}

class _ListenReminderHostState extends ConsumerState<ListenReminderHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<int>? _tapSub;
  bool _showing = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// Récupère d'abord un éventuel tap de notification (démarrage à froid),
  /// puis écoute les suivants, puis fait le premier contrôle : ainsi une
  /// notification touchée n'est jamais suivie du même rappel en pop-up.
  Future<void> _bootstrap() async {
    try {
      await ReminderNotificationService.init();
    } catch (_) {}
    if (!mounted) return;
    final pending = ReminderNotificationService.takePendingTap();
    _tapSub = ReminderNotificationService.taps.listen(_openFromNotification);
    if (pending != null) await _openFromNotification(pending);
    await _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tapSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      _check();
    } else if (state == AppLifecycleState.paused) {
      // On quitte l'app : les notifications annulées pour laisser la place
      // au pop-up doivent revenir (sinon un rappel serait perdu).
      unawaited(ref
          .read(listenHistoryProvider.notifier)
          .rescheduleUpcoming()
          .catchError((_) {}));
    }
  }

  Future<void> _openFromNotification(int trackId) async {
    if (!mounted) return;
    final notifier = ref.read(listenHistoryProvider.notifier);
    await notifier.ensureLoaded();
    if (!mounted) return;

    // La notification a été vue : pas de pop-up en double pour ce morceau.
    final now = DateTime.now();
    final seen = notifier
        .pendingReminders(now)
        .where((r) => r.event.trackId == trackId && !now.isBefore(r.scheduledAt))
        .toList();
    if (seen.isNotEmpty) await notifier.markShown(seen);

    // Au démarrage à froid, la bibliothèque peut ne pas être chargée.
    for (var i = 0; i < 24 && mounted; i++) {
      final state = ref.read(trackProvider);
      final track = state.tracks.where((t) => t.id == trackId).firstOrNull;
      if (track != null && mounted) {
        openPlayer(context, track: track, tracks: state.tracks);
        return;
      }
      if (!state.isLoading && state.tracks.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _check() async {
    // En arrière-plan (ex. musique qui continue de jouer), c'est la
    // notification qui doit s'afficher : on ne touche à rien.
    if (!mounted || _showing || _lifecycle != AppLifecycleState.resumed) return;

    final notifier = ref.read(listenHistoryProvider.notifier);
    await notifier.ensureLoaded();
    if (!mounted) return;

    // `pendingReminders` écarte déjà « il y a une heure » et « hier »
    // tant qu'une musique est en lecture : aucun pop-up pendant l'écoute.
    final now = DateTime.now();
    final pending = notifier.pendingReminders(now);
    if (pending.isEmpty) return;

    for (final r in pending) {
      unawaited(ReminderNotificationService.cancel(r.notificationId)
          .catchError((_) {}));
    }

    final due = pending.where((r) => !now.isBefore(r.scheduledAt)).toList();
    if (due.isEmpty) return;

    final library = ref.read(trackProvider).tracks;
    final items = <(ListenReminder, Track)>[];
    final seen = <int>{};
    for (final r in due) {
      final track = library.where((t) => t.id == r.event.trackId).firstOrNull;
      if (track != null && seen.add(track.id)) items.add((r, track));
    }

    // Marqués comme présentés dans tous les cas : un rappel dont le
    // morceau a disparu de la bibliothèque ne doit pas revenir.
    await notifier.markShown(due);
    if (items.isEmpty || !mounted) return;

    _showing = true;
    try {
      final picked = await Navigator.of(context).push<Track>(
        PageRouteBuilder<Track>(
          pageBuilder: (_, _, _) =>
              ListenReminderScreen(items: items.take(5).toList()),
          transitionsBuilder: (_, a, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 420),
        ),
      );
      if (picked != null && mounted) {
        openPlayer(
          context,
          track: picked,
          tracks: items.map((i) => i.$2).toList(),
        );
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
