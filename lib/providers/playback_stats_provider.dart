import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';
import 'listen_history_provider.dart';
import 'profile_provider.dart';
import 'track_provider.dart';

/// Suit les écoutes *réelles* : un morceau ne compte que lorsqu'il a été
/// écouté au-delà de 80 % de sa durée. Lancer un morceau puis le zapper
/// au bout de dix secondes ne doit rien ajouter — c'est toute la
/// différence entre « le plus lancé » et « le plus écouté ».
///
/// Le suivi s'appuie sur la position rapportée par le service audio
/// plutôt que sur l'événement « fin de piste » : une piste passée en
/// avance rapide sur les 10 dernières secondes compte quand même, et un
/// skip à 20 % ne compte pas.
class PlaybackStatsNotifier extends StateNotifier<Map<int, int>> {
  final StorageService _storage;
  final Ref _ref;

  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<PlaybackState>? _playbackSub;

  /// Id du morceau en cours, tel que connu du service audio.
  int? _currentTrackId;

  /// Durée du morceau en cours (ms), 0 si inconnue.
  int _currentDurationMs = 0;

  /// Évite de compter plusieurs fois la même écoute : remis à false
  /// uniquement lorsqu'on change de morceau, ou lorsque la lecture
  /// repart du tout début (réécoute complète).
  bool _countedForCurrent = false;

  /// Seuil au-delà duquel une écoute est considérée comme « réelle ».
  static const double _threshold = 0.8;

  PlaybackStatsNotifier(this._storage, this._ref) : super(const {}) {
    _load();
    _listen();
  }

  Future<void> _load() async {
    final counts = await _storage.getPlayCounts();
    if (mounted) state = counts;
  }

  Future<void> _listen() async {
    try {
      final handler = await _ref.read(audioHandlerProvider.future);

      _mediaItemSub = handler.mediaItem.listen((item) {
        final id = item == null ? null : int.tryParse(item.id);
        if (id != _currentTrackId) {
          _currentTrackId = id;
          _countedForCurrent = false;
        }
        _currentDurationMs = item?.duration?.inMilliseconds ?? 0;
      });

      _playbackSub = handler.playbackState.listen((playbackState) {
        final id = _currentTrackId;
        if (id == null) return;

        final positionMs = playbackState.updatePosition.inMilliseconds;

        // Retour au début : la piste est rejouée, on réarme le compteur.
        if (_countedForCurrent && positionMs < 1500) {
          _countedForCurrent = false;
          return;
        }

        if (_countedForCurrent) return;

        final durationMs = _currentDurationMs;
        // Durée inconnue (métadonnées manquantes) : on ne peut pas
        // calculer un pourcentage fiable, donc on ne compte rien plutôt
        // que de gonfler les statistiques au hasard.
        if (durationMs <= 0) return;

        if (positionMs >= durationMs * _threshold) {
          _countedForCurrent = true;
          _register(id);
        }
      });
    } catch (_) {
      // Le service audio n'a pas pu démarrer : la lecture elle-même est
      // déjà cassée, inutile de faire remonter une seconde erreur ici.
    }
  }

  Future<void> _register(int trackId) async {
    final counts = await _storage.incrementPlayCount(trackId);
    if (mounted) state = counts;

    // Rappel « même heure demain / la semaine prochaine » : seule la
    // première écoute réelle de chaque ouverture de l'app est retenue
    // (le filtre est dans ListenHistoryNotifier).
    final track = _ref
        .read(trackProvider)
        .tracks
        .where((t) => t.id == trackId)
        .firstOrNull;
    if (track != null) {
      unawaited(_ref
          .read(listenHistoryProvider.notifier)
          .recordFirstListenOfSession(track)
          .catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _mediaItemSub?.cancel();
    _playbackSub?.cancel();
    super.dispose();
  }
}

/// Volontairement *non* autoDispose : le suivi doit rester actif tant que
/// l'app tourne, même si aucun écran n'affiche les statistiques à cet
/// instant.
final playbackStatsProvider =
    StateNotifierProvider<PlaybackStatsNotifier, Map<int, int>>((ref) {
  return PlaybackStatsNotifier(ref.watch(storageServiceProvider), ref);
});

/// Morceaux ajoutés le plus récemment à la bibliothèque.
final recentlyAddedTracksProvider = Provider<List<Track>>((ref) {
  final tracks = List<Track>.from(ref.watch(trackProvider).tracks);
  tracks.sort((a, b) =>
      (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  return tracks.take(20).toList();
});

/// Morceaux les plus écoutés (≥ 80 % de la durée), du plus au moins joué.
final mostPlayedTracksProvider = Provider<List<Track>>((ref) {
  final counts = ref.watch(playbackStatsProvider);
  if (counts.isEmpty) return const [];

  final tracks = ref
      .watch(trackProvider)
      .tracks
      .where((t) => (counts[t.id] ?? 0) > 0)
      .toList();

  tracks.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
  return tracks.take(20).toList();
});

/// Morceaux marqués comme favoris.
final likedTracksProvider = Provider<List<Track>>((ref) {
  return ref.watch(trackProvider).tracks.where((t) => t.isLiked).toList();
});

/// Suggestions « à réécouter » : construites à partir des ambiances et des
/// artistes qui reviennent le plus dans ce que l'utilisateur écoute et
/// aime vraiment, en excluant ce qui est déjà dans ces deux listes pour
/// que la section propose bien autre chose plutôt que de recopier les
/// précédentes.
///
/// Pour un nouveau profil sans historique d'écoute, les 3 artistes
/// préférés choisis à l'onboarding servent de base : sans ça, cette
/// section resterait vide jusqu'à ce que l'utilisateur ait déjà écouté ou
/// aimé plusieurs morceaux, ce qui rend la question de l'onboarding
/// inutile en pratique.
final suggestedTracksProvider = Provider<List<Track>>((ref) {
  final counts = ref.watch(playbackStatsProvider);
  final allTracks = ref.watch(trackProvider).tracks;
  if (allTracks.isEmpty) return const [];

  final favoriteArtists = ref
      .watch(profileProvider)
      .favoriteArtists
      .map((a) => a.toLowerCase())
      .toSet();

  final seeds = <Track>[
    ...allTracks.where((t) => (counts[t.id] ?? 0) > 0),
    ...allTracks.where((t) => t.isLiked),
  ];

  if (seeds.isEmpty) {
    if (favoriteArtists.isEmpty) return const [];
    // Cold start : rien écouté ni aimé pour le moment, mais des artistes
    // préférés existent - ce sont eux qui remplissent les 20 morceaux
    // proposés, plutôt qu'une section vide.
    final fromFavorites = allTracks
        .where((t) => favoriteArtists.contains(t.artist.toLowerCase()))
        .toList();
    return fromFavorites.take(20).toList();
  }

  final seedIds = seeds.map((t) => t.id).toSet();

  // Poids par ambiance et par artiste, pondérés par le nombre d'écoutes
  // réelles (un favori compte pour une écoute de base).
  final moodScores = <MoodType, int>{};
  final artistScores = <String, int>{};
  for (final track in seeds) {
    final weight = (counts[track.id] ?? 0) + (track.isLiked ? 1 : 0);
    final mood = track.mood;
    if (mood != null && mood != MoodType.unknown) {
      moodScores[mood] = (moodScores[mood] ?? 0) + weight;
    }
    final artist = track.artist.toLowerCase();
    artistScores[artist] = (artistScores[artist] ?? 0) + weight;
  }
  // Boost fixe pour les artistes choisis à l'onboarding, même s'ils n'ont
  // encore généré aucune écoute/favori - le choix explicite de
  // l'utilisateur doit peser, pas seulement son comportement passé.
  for (final artist in favoriteArtists) {
    artistScores[artist] = (artistScores[artist] ?? 0) + 3;
  }

  final candidates = allTracks.where((t) => !seedIds.contains(t.id)).toList();

  int scoreOf(Track track) {
    var score = 0;
    final mood = track.mood;
    if (mood != null) score += (moodScores[mood] ?? 0) * 2;
    score += (artistScores[track.artist.toLowerCase()] ?? 0) * 3;
    return score;
  }

  final scored = candidates.map((t) => (t, scoreOf(t))).where((e) => e.$2 > 0).toList();
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).take(20).toList();
});
