import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listen_event.dart';
import '../models/track.dart';
import '../services/listen_history_service.dart';
import '../services/reminder_notification_service.dart';

class ListenHistoryState {
  final List<ListenEvent> events;
  final Set<String> shown;

  const ListenHistoryState({this.events = const [], this.shown = const {}});
}

/// Mémorise LA première écoute réelle (≥ 80 %) de chaque ouverture de
/// l'app, pour la reproposer le lendemain puis une semaine plus tard à la
/// même heure. Une seule écoute par ouverture, volontairement : proposer
/// tous les morceaux écoutés reviendrait à bombarder l'utilisateur.
///
/// « Ouverture » = vie du processus de l'app : le drapeau
/// [_recordedThisSession] est remis à zéro quand l'app est fermée puis
/// relancée, pas quand elle passe simplement en arrière-plan.
class ListenHistoryNotifier extends StateNotifier<ListenHistoryState> {
  final ListenHistoryService _service;
  late final Future<void> _ready;
  bool _recordedThisSession = false;

  /// Au-delà de 8 jours, ni le rappel du lendemain ni celui de la semaine
  /// suivante ne peuvent plus arriver : on jette l'écoute.
  static const Duration _retention = Duration(days: 8);

  /// Fenêtre pendant laquelle un rappel reste proposé après son heure.
  static const Duration _window = Duration(minutes: 60);

  ListenHistoryNotifier(this._service) : super(const ListenHistoryState()) {
    _ready = _load();
  }

  Future<void> ensureLoaded() => _ready;

  Future<void> _load() async {
    final data = await _service.load();
    if (mounted) {
      state = _pruned(
        ListenHistoryState(events: data.events, shown: data.shown),
        DateTime.now(),
      );
    }
  }

  ListenHistoryState _pruned(ListenHistoryState s, DateTime now) {
    final events =
        s.events.where((e) => e.at.add(_retention).isAfter(now)).toList();
    final ids = events.map((e) => '${e.id}').toSet();
    final shown = s.shown.where((k) => ids.contains(k.split(':').first)).toSet();
    return ListenHistoryState(events: events, shown: shown);
  }

  Future<void> _persist() =>
      _service.save(ListenHistoryData(events: state.events, shown: state.shown));

  /// À appeler à chaque écoute réelle ; ne retient que la première de la
  /// session.
  Future<void> recordFirstListenOfSession(Track track) async {
    if (_recordedThisSession) return;
    _recordedThisSession = true;

    await _ready;
    if (!mounted) return;

    final now = DateTime.now();
    final mood = track.mood;
    final event = ListenEvent(
      id: now.millisecondsSinceEpoch,
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      mood: (mood == null || mood == MoodType.unknown) ? null : mood.name,
      at: now,
    );

    state = _pruned(
      ListenHistoryState(events: [...state.events, event], shown: state.shown),
      now,
    );
    await _persist();

    try {
      await ReminderNotificationService.requestPermission();
      for (final kind in ReminderKind.values) {
        await ReminderNotificationService.schedule(ListenReminder(event, kind));
      }
    } catch (_) {
      // Les notifications sont un bonus : ne jamais faire échouer le suivi
      // d'écoute pour ça.
    }
  }

  /// Rappels proposables maintenant (heure atteinte, depuis moins d'une
  /// heure, jamais présentés), plus ceux qui arrivent dans les 45 s : ces
  /// derniers servent à annuler leur notification quand l'app est ouverte.
  List<ListenReminder> pendingReminders(DateTime now) {
    final result = <ListenReminder>[];
    for (final event in state.events) {
      for (final kind in ReminderKind.values) {
        final reminder = ListenReminder(event, kind);
        if (state.shown.contains(reminder.key)) continue;
        final elapsed = now.difference(reminder.scheduledAt);
        if (elapsed >= const Duration(seconds: -45) && elapsed < _window) {
          result.add(reminder);
        }
      }
    }
    return result;
  }

  Future<void> markShown(Iterable<ListenReminder> reminders) async {
    state = ListenHistoryState(
      events: state.events,
      shown: {...state.shown, ...reminders.map((r) => r.key)},
    );
    await _persist();
  }
}

final listenHistoryServiceProvider =
    Provider<ListenHistoryService>((ref) => ListenHistoryService());

/// Non autoDispose : le drapeau « déjà enregistré cette session » doit
/// vivre aussi longtemps que l'app.
final listenHistoryProvider =
    StateNotifierProvider<ListenHistoryNotifier, ListenHistoryState>((ref) {
  return ListenHistoryNotifier(ref.watch(listenHistoryServiceProvider));
});
