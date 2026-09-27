import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import 'audio_provider.dart';
import 'profile_provider.dart';
import 'track_provider.dart';

/// "Lecture intelligente" : tant que `profile.smartQueueEnabled` est actif,
/// dès que la piste en cours dépasse 50% de sa durée, la prochaine piste de
/// la file est remplacée par une piste de la même ambiance - de préférence
/// du même artiste - plutôt que de suivre la file d'attente prévue.
///
/// - La décision est prise une seule fois par piste (au premier tick qui
///   franchit 50%), jamais réévaluée ensuite pour cette même piste.
/// - S'il n'existe aucune piste de la même ambiance dans la bibliothèque,
///   on ne touche à rien : la file d'attente d'origine continue.
/// - On évite autant que possible de reproposer une piste déjà entendue
///   pendant la session en cours.
/// - Seule la toute prochaine piste est remplacée ; le reste de la file
///   d'attente d'origine n'est pas perturbé (voir `playNext` côté handler).
///
/// Instancié une seule fois pour toute la durée de vie de l'app (lu depuis
/// [MainShell], qui reste monté en permanence) : ce n'est pas un
/// [Provider.autoDispose], donc les `ref.listen` posés dans le constructeur
/// restent actifs même si aucun écran n'observe la position à cet instant.
final smartQueueControllerProvider = Provider<SmartQueueController>((ref) {
  final controller = SmartQueueController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class SmartQueueController {
  SmartQueueController(this._ref) {
    // Nouvelle piste en cours : on réautorise une nouvelle décision, et on
    // note cette piste comme "récemment écoutée" pour la session.
    _ref.listen<AsyncValue<MediaItem?>>(
      currentTrackProvider,
      (previous, next) {
        final item = next.valueOrNull;
        if (item == null) return;
        if (previous?.valueOrNull?.id == item.id) return;

        _decidedForTrackId = null;
        _recentlyPlayed.remove(item.id);
        _recentlyPlayed.add(item.id);
        if (_recentlyPlayed.length > _recentHistoryLimit) {
          _recentlyPlayed.removeAt(0);
        }
      },
      fireImmediately: true,
    );

    // Chaque mise à jour de position est l'occasion de vérifier le seuil
    // de 50% pour la piste actuellement en cours.
    _ref.listen<AsyncValue<PlaybackState>>(
      playbackStateProvider,
      (previous, next) => _maybeSubstituteNext(next.valueOrNull?.updatePosition),
    );
  }

  static const int _recentHistoryLimit = 30;

  final Ref _ref;
  final Random _random = Random();
  final List<String> _recentlyPlayed = [];
  String? _decidedForTrackId;

  void _maybeSubstituteNext(Duration? position) {
    if (position == null) return;

    final profile = _ref.read(profileProvider);
    if (!profile.smartQueueEnabled) return;

    final current = _ref.read(currentTrackProvider).valueOrNull;
    if (current == null) return;
    if (_decidedForTrackId == current.id) return; // déjà décidé pour cette piste

    final duration = _ref.read(durationProvider).valueOrNull;
    if (duration == null || duration.inMilliseconds <= 0) return;
    if (position.inMilliseconds / duration.inMilliseconds < 0.5) return;

    // Une seule tentative par piste, que ça aboutisse ou non - on ne veut
    // pas retenter à chaque tick suivant une fois le seuil franchi.
    _decidedForTrackId = current.id;

    final library = _ref.read(trackProvider).tracks;
    final currentTrack = _findTrackById(library, current.id);
    final mood = currentTrack?.mood;
    if (mood == null) return; // piste non classifiée : file d'origine inchangée

    final sameMood = library
        .where((t) => t.mood == mood && t.id.toString() != current.id)
        .toList();
    if (sameMood.isEmpty) return; // aucune piste de cette ambiance : on ne touche à rien

    final artist = currentTrack!.artist.trim().toLowerCase();
    final sameArtist = artist.isEmpty
        ? const <Track>[]
        : sameMood.where((t) => t.artist.trim().toLowerCase() == artist).toList();

    final pick = _pickPreferablyUnplayed(sameArtist) ?? _pickPreferablyUnplayed(sameMood);
    if (pick == null) return;

    _ref.read(audioHandlerProvider.future).then((handler) => handler.playNext(pick));
  }

  Track? _findTrackById(List<Track> tracks, String id) {
    for (final t in tracks) {
      if (t.id.toString() == id) return t;
    }
    return null;
  }

  /// Choisit une piste au hasard dans [pool], en excluant celles déjà
  /// écoutées récemment dans la session quand c'est possible.
  Track? _pickPreferablyUnplayed(List<Track> pool) {
    if (pool.isEmpty) return null;
    final unplayed =
        pool.where((t) => !_recentlyPlayed.contains(t.id.toString())).toList();
    final effective = unplayed.isNotEmpty ? unplayed : pool;
    return effective[_random.nextInt(effective.length)];
  }

  void dispose() {}
}
