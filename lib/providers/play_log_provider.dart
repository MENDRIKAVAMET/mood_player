import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/play_log_entry.dart';
import '../models/track.dart';
import '../services/play_log_service.dart';

/// Journal des écoutes réelles, alimenté par `PlaybackStatsNotifier` au
/// moment où une écoute passe le seuil des 80 %. Sert au bilan du mois.
class PlayLogNotifier extends StateNotifier<List<PlayLogEntry>> {
  final PlayLogService _service;
  late final Future<void> _ready;

  /// Au-delà, les écoutes les plus anciennes sont jetées : le bilan est
  /// mensuel, un an de recul suffit largement.
  static const Duration retention = Duration(days: 400);

  /// Plafond de sécurité (≈ 2 Mo de JSON) pour un fichier toujours rapide à
  /// réécrire.
  static const int maxEntries = 20000;

  PlayLogNotifier(this._service) : super(const []) {
    _ready = _load();
  }

  Future<void> _load() async {
    final loaded = await _service.load();
    if (!mounted) return;
    // Les écoutes enregistrées pendant le chargement (improbable) sont
    // conservées.
    state = prune([...loaded, ...state], DateTime.now());
  }

  /// Ajoute une écoute de [track] qui vient d'être terminée.
  Future<void> record(Track track, {DateTime? at}) async {
    await _ready;
    if (!mounted) return;
    final now = at ?? DateTime.now();
    final entry = PlayLogEntry(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      mood: track.mood?.name,
      at: now,
    );
    state = prune([...state, entry], now);
    await _service.save(state);
  }

  /// Retire les écoutes trop anciennes, puis garde les [maxEntries] plus
  /// récentes (la liste est chronologique).
  @visibleForTesting
  static List<PlayLogEntry> prune(List<PlayLogEntry> entries, DateTime now) {
    final cutoff = now.subtract(retention);
    final kept = [
      for (final e in entries)
        if (!e.at.isBefore(cutoff)) e,
    ];
    if (kept.length <= maxEntries) return kept;
    return kept.sublist(kept.length - maxEntries);
  }
}

/// Volontairement *non* autoDispose : le journal doit rester chargé tant que
/// l'app tourne, pour ne rien perdre quand aucun écran ne l'affiche.
final playLogProvider =
    StateNotifierProvider<PlayLogNotifier, List<PlayLogEntry>>((ref) {
  return PlayLogNotifier(PlayLogService());
});
