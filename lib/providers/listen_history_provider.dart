import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listen_event.dart';
import '../models/track.dart';
import '../services/listen_history_service.dart';
import '../services/reminder_notification_service.dart';
import 'audio_provider.dart';

class ListenHistoryState {
  final List<ListenEvent> events;
  final Set<String> shown;

  const ListenHistoryState({this.events = const [], this.shown = const {}});
}

/// Mémorise LA première écoute réelle (≥ 80 %) de chaque ouverture de
/// l'app, pour la reproposer une heure, un jour, une semaine et un mois plus tard
/// (les trois derniers à la même heure). Une seule écoute par ouverture, volontairement : proposer
/// tous les morceaux écoutés reviendrait à bombarder l'utilisateur.
///
/// « Ouverture » = vie du processus de l'app : le drapeau
/// [_recordedThisSession] est remis à zéro quand l'app est fermée puis
/// relancée, pas quand elle passe simplement en arrière-plan.
///
/// Les rappels « il y a une heure » et « hier » (voir
/// [ListenReminder.skipsWhilePlaying]) sont suspendus tant qu'une musique
/// est en lecture : leur notification est annulée au démarrage de la
/// lecture, reprogrammée à la pause, et un rappel dont l'heure tombe en
/// pleine lecture est abandonné.
class ListenHistoryNotifier extends StateNotifier<ListenHistoryState> {
  final ListenHistoryService _service;
  final Ref _ref;
  late final Future<void> _ready;
  bool _recordedThisSession = false;

  /// Une musique est-elle en lecture (et depuis quand) ?
  bool _isPlaying = false;
  DateTime? _playingSince;
  StreamSubscription<bool>? _playingSub;

  /// Au-delà de 31 jours, plus aucun rappel (le plus lointain est à un mois)
  /// ne peut arriver : on jette l'écoute.
  static const Duration _retention = Duration(days: 31);

  /// Fenêtre pendant laquelle un rappel reste proposé après son heure.
  static const Duration _window = Duration(minutes: 60);

  ListenHistoryNotifier(this._service, this._ref)
      : super(const ListenHistoryState()) {
    _ready = _load();
    _listenPlayback();
  }

  /// Suit l'état de lecture du service audio (même approche que
  /// `PlaybackStatsNotifier`).
  Future<void> _listenPlayback() async {
    try {
      final handler = await _ref.read(audioHandlerProvider.future);
      if (!mounted) return;
      _playingSub = handler.playbackState
          .map((s) => s.playing)
          .distinct()
          .listen(_onPlayingChanged);
    } catch (_) {
      // Le service audio n'a pas pu démarrer : il n'y a donc pas de
      // lecture à attendre, les rappels restent comme avant.
    }
  }

  void _onPlayingChanged(bool playing) {
    if (playing == _isPlaying) return;
    final since = _playingSince;
    _isPlaying = playing;
    _playingSince = playing ? DateTime.now() : null;
    unawaited(_syncWhilePlaying(playing, since).catchError((_) {}));
  }

  /// Applique le changement d'état de lecture aux rappels concernés.
  Future<void> _syncWhilePlaying(bool playing, DateTime? since) async {
    await _ready;
    if (!mounted) return;

    final now = DateTime.now();
    final skipped = <ListenReminder>[];
    for (final event in state.events) {
      for (final kind in ReminderKind.values) {
        // L'état a changé entre-temps : une autre synchro prend le relais.
        if (_isPlaying != playing || !mounted) return;

        final reminder = ListenReminder(event, kind);
        if (!reminder.skipsWhilePlaying || state.shown.contains(reminder.key)) {
          continue;
        }
        final upcoming = reminder.scheduledAt.isAfter(now);
        if (playing) {
          // La lecture démarre : plus de notification pour ceux-là.
          if (upcoming) {
            await ReminderNotificationService.cancel(reminder.notificationId);
          }
        } else if (upcoming) {
          // La lecture s'arrête : on reprogramme ceux qui sont à venir.
          await ReminderNotificationService.schedule(reminder);
        } else if (since != null && !reminder.scheduledAt.isBefore(since)) {
          // L'heure est tombée PENDANT la lecture : on l'abandonne plutôt
          // que de l'envoyer en retard à la pause.
          skipped.add(reminder);
        }
      }
    }
    if (skipped.isNotEmpty && mounted) await markShown(skipped);
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    super.dispose();
  }

  Future<void> ensureLoaded() => _ready;

  Future<void> _load() async {
    final data = await _service.load();
    if (mounted) {
      state = _pruned(
        ListenHistoryState(events: data.events, shown: data.shown),
        DateTime.now(),
      );
      unawaited(_rescheduleAll());
    }
  }

  /// À chaque ouverture de l'app, reprogramme les rappels à venir : une
  /// programmation qui avait échoué (ou été supprimée par le système) est
  /// ainsi rattrapée. Reprogrammer un rappel existant le remplace, sans
  /// doublon.
  Future<void> _rescheduleAll() async {
    try {
      final now = DateTime.now();
      for (final event in state.events) {
        for (final kind in ReminderKind.values) {
          final reminder = ListenReminder(event, kind);
          if (state.shown.contains(reminder.key)) continue;
          // Pendant une lecture, ceux-là sont reprogrammés à la pause.
          if (_isPlaying && reminder.skipsWhilePlaying) continue;
          if (reminder.scheduledAt.isAfter(now)) {
            await ReminderNotificationService.schedule(reminder);
          }
        }
      }
    } catch (_) {}
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
        final reminder = ListenReminder(event, kind);
        // On est en pleine lecture : « il y a une heure » et « hier » sont
        // programmés à la pause (voir _syncWhilePlaying).
        if (_isPlaying && reminder.skipsWhilePlaying) continue;
        await ReminderNotificationService.schedule(reminder);
      }
      await ReminderNotificationService.askBatteryExemptionOnce();
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
        // Pas de pop-up « il y a une heure » / « hier » pendant la lecture.
        if (_isPlaying && reminder.skipsWhilePlaying) continue;
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
  return ListenHistoryNotifier(ref.watch(listenHistoryServiceProvider), ref);
});
