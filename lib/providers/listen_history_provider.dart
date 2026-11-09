import 'dart:async';

import 'package:flutter/widgets.dart';
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

  /// Toutes les (re)programmations passent par cette file : une seule à la
  /// fois, dans l'ordre. Sans ça, une pause suivie d'une reprise immédiate
  /// pouvait laisser une notification « il y a une heure » programmée en
  /// pleine lecture.
  Future<void> _syncChain = Future.value();

  /// Entre deux morceaux, `playing` peut retomber à false une fraction de
  /// seconde : on attend un peu avant de considérer que la lecture s'est
  /// vraiment arrêtée (sauf si l'app est en arrière-plan, voir
  /// [_onPlayingChanged]).
  Timer? _stopDebounce;
  DateTime? _sinceBeforeBlip;
  static const Duration _stopDelay = Duration(milliseconds: 1500);

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

  bool get _appInForeground {
    try {
      final s = WidgetsBinding.instance.lifecycleState;
      return s == null || s == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  void _onPlayingChanged(bool playing) {
    if (playing == _isPlaying) return;
    _isPlaying = playing;

    if (playing) {
      // Reprise rapide après un « clignotement » : c'est la même session
      // d'écoute, on garde son vrai début.
      final blipSince = _sinceBeforeBlip;
      final wasPending = _stopDebounce?.isActive ?? false;
      _stopDebounce?.cancel();
      _sinceBeforeBlip = null;
      _playingSince = (wasPending && blipSince != null)
          ? blipSince
          : DateTime.now();
      // La lecture démarre : on retire tout de suite les notifications
      // « il y a une heure » / « hier » encore programmées.
      unawaited(_reconcile());
      return;
    }

    final since = _playingSince;
    _playingSince = null;
    if (_appInForeground) {
      // Évite de reprogrammer (puis annuler) à chaque changement de piste.
      _sinceBeforeBlip = since;
      _stopDebounce?.cancel();
      _stopDebounce = Timer(_stopDelay, () {
        _sinceBeforeBlip = null;
        if (!_isPlaying) unawaited(_reconcile(since: since));
      });
    } else {
      // App fermée / en arrière-plan (ex. retirée des applications
      // récentes) : le processus peut disparaître d'un instant à l'autre,
      // on reprogramme sans attendre.
      unawaited(_reconcile(since: since));
    }
  }

  Future<void> _reconcile({DateTime? since, bool all = false}) {
    final next = _syncChain
        .then((_) => _doReconcile(since: since, all: all))
        .catchError((_) {});
    _syncChain = next;
    return next;
  }

  /// Remet les notifications programmées en accord avec l'état de lecture :
  ///  - en lecture : « il y a une heure » et « hier » sont annulées ;
  ///  - à l'arrêt : celles à venir sont (re)programmées ; celles dont
  ///    l'heure est tombée PENDANT la lecture sont abandonnées plutôt
  ///    qu'envoyées en retard.
  /// Sans [all], seuls ces deux types de rappel sont concernés.
  Future<void> _doReconcile({DateTime? since, bool all = false}) async {
    await _ready;
    if (!mounted) return;

    final now = DateTime.now();
    final skipped = <ListenReminder>[];
    for (final event in List<ListenEvent>.of(state.events)) {
      for (final kind in ReminderKind.values) {
        if (!mounted) return;
        final reminder = ListenReminder(event, kind);
        if (state.shown.contains(reminder.key)) continue;
        if (!all && !reminder.skipsWhilePlaying) continue;

        final upcoming = reminder.scheduledAt.isAfter(now);
        // Lu à chaque tour : l'état peut changer pendant la boucle.
        if (_isPlaying && reminder.skipsWhilePlaying) {
          if (upcoming) {
            await ReminderNotificationService.cancel(reminder.notificationId);
          }
          continue;
        }
        if (upcoming) {
          await ReminderNotificationService.schedule(reminder);
        } else if (since != null &&
            reminder.skipsWhilePlaying &&
            !reminder.scheduledAt.isBefore(since)) {
          skipped.add(reminder);
        }
      }
    }
    if (skipped.isNotEmpty && mounted) await markShown(skipped);
  }

  /// À appeler quand l'app passe en arrière-plan : les notifications
  /// annulées pour laisser la place au pop-up sont reprogrammées.
  Future<void> rescheduleUpcoming() => _reconcile(all: true);

  @override
  void dispose() {
    _stopDebounce?.cancel();
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
  /// doublon. Pendant une lecture, « il y a une heure » / « hier » restent
  /// annulés (voir [_doReconcile]).
  Future<void> _rescheduleAll() => _reconcile(all: true);

  ListenHistoryState _pruned(ListenHistoryState s, DateTime now) {
    final events =
        s.events.where((e) => e.at.add(_retention).isAfter(now)).toList();
    final ids = events.map((e) => '${e.id}').toSet();
    final shown = s.shown.where((k) => ids.contains(k.split(':').first)).toSet();
    return ListenHistoryState(events: events, shown: shown);
  }

  Future<void> _persist() =>
      _service.save(ListenHistoryData(events: state.events, shown: state.shown));

  /// Pochette utilisable par la notification : un fichier local seulement.
  static String? _localCover(Track track) {
    final c = track.coverUrl;
    if (c == null || c.isEmpty) return null;
    if (c.startsWith('http://') || c.startsWith('https://')) return null;
    return c;
  }

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
      cover: _localCover(track),
      at: now,
    );

    state = _pruned(
      ListenHistoryState(events: [...state.events, event], shown: state.shown),
      now,
    );
    await _persist();

    try {
      await ReminderNotificationService.requestPermission();
      // En pleine lecture, « il y a une heure » et « hier » ne sont pas
      // programmés (voir _doReconcile) ; ils le seront à la pause.
      await _reconcile(all: true);
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
