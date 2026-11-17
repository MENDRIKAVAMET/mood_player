import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../models/track.dart';
import '../services/storage_service.dart';
import '../services/groq_service.dart';
import '../services/mood_correction_service.dart';
import '../services/genre_mood_classifier.dart';
import '../services/track_genre_store.dart';
import '../services/track_secondary_mood_store.dart';
import '../services/library_scan_service.dart';
import '../services/artwork_service.dart';
import '../services/ui_gate.dart';
import 'audio_provider.dart' show audioHandlerProvider;
import '../services/library_filter_service.dart';
import '../services/track_file_service.dart';
import '../utils/app_error.dart';

// Service providers
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final moodCorrectionServiceProvider = Provider<MoodCorrectionService>((ref) {
  return MoodCorrectionService();
});

final groqServiceProvider = Provider<GroqService>((ref) {
  return GroqService();
});

final libraryScanServiceProvider = Provider<LibraryScanService>((ref) {
  return LibraryScanService();
});

final artworkServiceProvider = Provider<ArtworkService>((ref) {
  return ArtworkService();
});

/// Available ways to sort the track list.
enum TrackSortOption {
  nameAsc,
  nameDesc,
  dateNewest,
  dateOldest,
}

extension TrackSortOptionLabel on TrackSortOption {
  String get label {
    switch (this) {
      case TrackSortOption.nameAsc:
        return 'Nom (A → Z)';
      case TrackSortOption.nameDesc:
        return 'Nom (Z → A)';
      case TrackSortOption.dateNewest:
        return 'Plus récent';
      case TrackSortOption.dateOldest:
        return 'Plus ancien';
    }
  }
}

// Track state
class TrackState {
  final List<Track> tracks;
  final List<Track> filteredTracks;
  final MoodType? selectedMood;
  final String searchQuery;
  final bool isLoading;
  final String? error;
  final TrackSortOption sortOption;
  final int? minDurationSeconds;

  /// Non-null while a batch classification is in progress; tracks how many
  /// of [classifyTotal] tracks have been processed so far, for the
  /// progress indicator.
  final int? classifyProgress;
  final int? classifyTotal;

  const TrackState({
    this.tracks = const [],
    this.filteredTracks = const [],
    this.selectedMood,
    this.searchQuery = '',
    this.isLoading = false,
    this.error,
    this.sortOption = TrackSortOption.dateNewest,
    this.minDurationSeconds,
    this.classifyProgress,
    this.classifyTotal,
  });

  bool get isClassifying => classifyTotal != null;

  TrackState copyWith({
    List<Track>? tracks,
    List<Track>? filteredTracks,
    MoodType? selectedMood,
    String? searchQuery,
    bool? isLoading,
    String? error,
    TrackSortOption? sortOption,
    int? minDurationSeconds,
    bool clearMinDurationSeconds = false,
    int? classifyProgress,
    int? classifyTotal,
    bool clearClassifyProgress = false,
  }) {
    return TrackState(
      tracks: tracks ?? this.tracks,
      filteredTracks: filteredTracks ?? this.filteredTracks,
      selectedMood: selectedMood ?? this.selectedMood,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sortOption: sortOption ?? this.sortOption,
      minDurationSeconds: clearMinDurationSeconds
          ? null
          : (minDurationSeconds ?? this.minDurationSeconds),
      classifyProgress: clearClassifyProgress
          ? null
          : (classifyProgress ?? this.classifyProgress),
      classifyTotal: clearClassifyProgress
          ? null
          : (classifyTotal ?? this.classifyTotal),
    );
  }
}

// Track notifier
class TrackNotifier extends StateNotifier<TrackState> {
  final StorageService _storageService;
  final GroqService _groqService;
  final MoodCorrectionService? _correctionService;
  final LibraryScanService _libraryScanService;
  final ArtworkService _artworkService;

  /// Prévenu quand un « j'aime » change dans l'app, pour mettre à jour le
  /// cœur de la notification de lecture.
  final void Function(int trackId, bool liked)? onLikedChanged;

  TrackNotifier(
    this._storageService,
    this._groqService,
    this._libraryScanService,
    this._artworkService, {
    this.onLikedChanged,
    MoodCorrectionService? correctionService,
  })  : _correctionService = correctionService,
        super(const TrackState());

  /// Durée maximale du squelette de chargement à l'ouverture. Passé ce
  /// délai, on montre ce qui est déjà en base (voir [scanAndLoadTracks]).
  static const Duration _maxLoaderWait = Duration(milliseconds: 1500);

  final LibraryFilterService _filterService = LibraryFilterService();
  bool _filterLoaded = false;

  /// Recharge le filtre de durée enregistré, une seule fois. Appelé avant le
  /// premier chargement de la liste : sans ça, le filtre saisi la fois
  /// d'avant était perdu au redémarrage et les morceaux courts revenaient.
  Future<void> _ensureFilterLoaded() async {
    if (_filterLoaded) return;
    _filterLoaded = true;
    final saved = await _filterService.loadMinDurationSeconds();
    // Si l'utilisateur a déjà réglé un filtre pendant ce temps, il prime.
    if (saved != null && state.minDurationSeconds == null) {
      state = state.copyWith(minDurationSeconds: saved);
    }
  }

  /// Extrait les pochettes encore absentes du cache, une à la fois, en tâche
  /// de fond.
  ///
  /// Pour ne jamais gêner l'écran :
  ///  * chaque extraction attend que l'écran soit tranquille ([UiGate]) ;
  ///  * les morceaux sont mis à jour en place : une ligne qui entre à l'écran
  ///    affiche déjà sa pochette sans qu'on ait besoin de reconstruire la liste ;
  ///  * la liste n'est rafraîchie que par gros lots, au plus toutes les 3 s,
  ///    et jamais pendant un défilement ; ni tri ni filtre ne dépendent de la
  ///    pochette, on ne les rejoue donc pas.
  Future<void> _backfillArtwork(
    Map<String, int> mediaStoreIdByPath,
    ArtworkCacheIndex artCache,
  ) async {
    if (mediaStoreIdByPath.isEmpty) return;

    final missing = <String, int>{};
    for (final entry in mediaStoreIdByPath.entries) {
      if (artCache.needsExtraction(entry.value)) {
        missing[entry.key] = entry.value;
      }
    }
    if (missing.isEmpty) return;

    final gate = UiGate.instance;

    Map<String, Track> indexByPath(List<Track> tracks) => {
          for (final t in tracks)
            if (t.filePath != null) t.filePath!: t,
        };

    // Table chemin -> morceau construite une fois ; reconstruite seulement si
    // la liste de l'état a été remplacée entre-temps.
    var snapshot = state.tracks;
    var byPath = indexByPath(snapshot);

    final pending = <Track>[];
    final sincePublish = Stopwatch()..start();

    Future<void> publish({bool force = false}) async {
      if (pending.isEmpty) return;
      if (!force &&
          (pending.length < 100 ||
              sincePublish.elapsedMilliseconds < 3000 ||
              gate.isBusy)) {
        return;
      }
      if (force) await gate.idle();
      if (!mounted) return;
      final batch = List<Track>.from(pending);
      pending.clear();
      sincePublish.reset();
      await _storageService.saveTracks(batch);
      if (!mounted) return;
      state = state.copyWith(
        tracks: List<Track>.from(state.tracks),
        filteredTracks: List<Track>.from(state.filteredTracks),
      );
      snapshot = state.tracks;
    }

    for (final entry in missing.entries) {
      if (!mounted) return;
      // Une extraction native à la fois, seulement quand l'écran est calme.
      await gate.idle(minGap: const Duration(milliseconds: 20));
      final path = await _artworkService.extract(entry.value, knownMissing: true);
      if (path == null) continue;
      if (!mounted) return;

      if (!identical(snapshot, state.tracks)) {
        snapshot = state.tracks;
        byPath = indexByPath(snapshot);
      }

      final track = byPath[entry.key];
      if (track == null) continue;

      track.coverUrl = path;
      pending.add(track);

      await publish();
    }

    await publish(force: true);
  }

  /// Load all tracks from storage
  Future<void> loadTracks() async {
    await _ensureFilterLoaded();
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final tracks = await _storageService.getAllTracks();
      state = state.copyWith(
        tracks: tracks,
        filteredTracks: tracks,
        isLoading: false,
      );
      _applyFilters();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors du chargement des morceaux. ${friendlyError(e)}',
      );
    }
  }

  /// Relit la base SANS passer par `isLoading`. `loadTracks()` met `isLoading`
  /// à vrai, ce qui remplace la liste par des squelettes : si la liste est
  /// déjà à l'écran, elle disparaît et la position de défilement est perdue
  /// (c'est ce qui donnait l'impression d'une liste « coincée »).
  Future<void> _reloadQuietly() async {
    final tracks = await _storageService.getAllTracks();
    if (!mounted) return;
    state = state.copyWith(
      tracks: tracks,
      filteredTracks: tracks,
      isLoading: false,
    );
    _applyFilters();
  }

  /// Scan the device's entire audio library (every format the OS indexes),
  /// merge the results into local storage (updating already-known tracks
  /// with fresh metadata/duration while preserving their mood
  /// classification), then reload. Runs on every app open.
  ///
  /// Pensé pour que l'ouverture soit rapide ET fluide :
  ///  1. chargement d'abord : le squelette s'affiche tant que la bibliothèque
  ///     n'est pas prête, puis la liste apparaît d'un bloc, déjà à jour (plus
  ///     de remplissage petit à petit pendant qu'on défile). Le squelette ne
  ///     dure jamais plus de [_maxLoaderWait] : au-delà, on montre la base
  ///     existante et le scan finit en tâche de fond (une seule mise à jour,
  ///     hors défilement) ;
  ///  2. mise à jour par différences : seuls les morceaux nouveaux ou
  ///     modifiés sont écrits, et la liste n'est relue que si quelque chose
  ///     a changé (cas le plus courant : rien, donc zéro écriture) ;
  ///  3. cache des pochettes lu en un seul listing de dossier.
  ///
  /// [showCachedWhileScanning] : à vrai (défaut), au bout de [_maxLoaderWait]
  /// la base existante est montrée pendant que le scan finit. À faux, on ne
  /// relit rien avant la fin du scan : utilisé par l'écran de démarrage
  /// (StartupGate), qui attend de toute façon le scan avant d'afficher l'app,
  /// et évite ainsi une double lecture + un double tri de toute la base.
  Future<void> scanAndLoadTracks({bool showCachedWhileScanning = true}) async {
    await _ensureFilterLoaded();

    // 1. Chargement d'abord (squelette), avec garde-fou de durée. Si la liste
    // est déjà à l'écran (relance manuelle du scan), on ne la masque pas.
    final initialLoad = state.tracks.isEmpty;
    var shownFromCache = false;
    Timer? loaderGuard;
    state = state.copyWith(isLoading: initialLoad, error: null);
    if (initialLoad && showCachedWhileScanning) {
      loaderGuard = Timer(_maxLoaderWait, () async {
        if (!mounted || !state.isLoading) return;
        try {
          // Premier lancement : rien en base, le squelette reste.
          if (await _storageService.getTrackCount() == 0) return;
          shownFromCache = true;
          await _reloadQuietly();
        } catch (_) {
          // Le scan en cours finira par afficher la liste de toute façon.
        }
      });
    }

    try {
      final result = await _libraryScanService.scan();

      if (!result.permissionGranted) {
        // No permission: fall back to whatever is already stored locally.
        if (state.tracks.isEmpty) await _reloadQuietly();
        final permanentlyDenied =
            await _libraryScanService.isPermissionPermanentlyDenied();
        state = state.copyWith(
          isLoading: false,
          error: permanentlyDenied
              ? 'Autorisation d\'accès à la musique définitivement refusée. '
                  'Activez-la dans les paramètres de l\'application.'
              : 'Autorisation d\'accès à la musique refusée. '
                  'Activez-la dans les paramètres pour scanner votre bibliothèque.',
        );
        return;
      }

      if (result.songs.isEmpty) {
        // Permission is granted but the OS reports no audio at all. Say so
        // explicitly - otherwise this is indistinguishable from a bug,
        // since the screen just shows an empty list either way.
        if (state.tracks.isEmpty) await _reloadQuietly();
        state = state.copyWith(isLoading: false);
        if (state.tracks.isEmpty) {
          state = state.copyWith(
            error: 'Aucun fichier audio trouvé sur cet appareil. '
                'Si vous avez de la musique, elle n\'est peut-être pas encore '
                'indexée par le système.',
          );
        }
        return;
      }

      // Titres/artistes modifiés par l'utilisateur : le scan ne doit pas
      // les remplacer par ceux (anciens) des tags du fichier.
      final nameOverrides = await TrackNameOverrides.load();
      final removedPaths = await RemovedTracks.load();

      // Morceaux déjà connus : ceux de l'état (chargés depuis la base juste
      // au-dessus), sans relire toute la base une deuxième fois.
      final existingTracks = state.tracks.isNotEmpty
          ? state.tracks
          : await _storageService.getAllTracks();
      final byFilePath = <String, Track>{
        for (final t in existingTracks)
          if (t.filePath != null) t.filePath!: t,
      };

      // Pochettes déjà en cache : un seul listing de dossier.
      final artCache = await _artworkService.loadCacheIndex();

      final now = DateTime.now();
      final toSave = <Track>[];

      // Le chemin d'un fichier ne permet pas de retrouver sa pochette :
      // elle est dans les tags, et seul MediaStore sait l'en extraire, à
      // partir de l'identifiant du morceau. On garde donc la
      // correspondance chemin -> id pour la passe d'extraction qui suit.
      final mediaStoreIdByPath = <String, int>{};

      // Genre des tags, par chemin : sert au pré-classement local et d'indice
      // pour Groq. Absent sur certains appareils / Android anciens : alors
      // tout passe par Groq, comme avant.
      final genreByPath = <String, String>{};

      var scanned = 0;
      for (final SongModel song in result.songs) {
        // Une grosse bibliothèque = des milliers d'itérations : on rend la
        // main à l'UI régulièrement au lieu de bloquer le thread d'un bloc.
        if (++scanned % 400 == 0) await Future<void>.delayed(Duration.zero);
        final filePath = song.data;
        if (filePath.isEmpty) continue;
        // Morceau retiré par l'utilisateur : on ne le remet pas.
        if (removedPaths.contains(filePath)) continue;

        mediaStoreIdByPath[filePath] = song.id;

        final rawGenre = song.getMap['genre'];
        if (rawGenre is String) {
          final g = rawGenre.trim();
          if (g.isNotEmpty && g.toLowerCase() != '<unknown>' && g.toLowerCase() != 'unknown') {
            genreByPath[filePath] = g;
          }
        }

        // Pochette déjà extraite lors d'un scan précédent : consultation de
        // l'index en mémoire, aucun accès disque ni appel natif.
        final cachedArt = artCache.pathFor(song.id);

        final existing = byFilePath[filePath];
        if (existing != null) {
          // Update metadata/duration for an already-known track, keep its
          // mood classification and creation date intact. On ne le marque
          // « à sauvegarder » que si quelque chose a réellement changé.
          final custom = nameOverrides[filePath];
          final newTitle = custom?['title'] ??
              (song.title.isNotEmpty ? song.title : existing.title);
          final newArtist = custom?['artist'] ??
              ((song.artist != null && song.artist!.isNotEmpty)
                  ? song.artist!
                  : existing.artist);
          final newAlbum = song.album ?? existing.album;
          final newDuration = song.duration ?? existing.duration;
          final newUri = song.uri ?? existing.uri;
          final newCover = cachedArt ?? existing.coverUrl;

          final changed = existing.title != newTitle ||
              existing.artist != newArtist ||
              existing.album != newAlbum ||
              existing.duration != newDuration ||
              existing.uri != newUri ||
              existing.coverUrl != newCover;

          if (changed) {
            existing
              ..title = newTitle
              ..artist = newArtist
              ..album = newAlbum
              ..duration = newDuration
              ..uri = newUri
              ..coverUrl = newCover
              ..updatedAt = now;
            toSave.add(existing);
          }
        } else {
          // Use the device's actual "date added" from MediaStore rather
          // than the scan time. Using DateTime.now() here made every
          // track added in the same scan (e.g. right after a fresh
          // install, or after StorageService's corruption-recovery reset)
          // get virtually the same timestamp, which made "Plus récent" /
          // "Plus ancien" sorting look broken since there was nothing
          // meaningful left to sort by. The real per-file date from the OS
          // stays meaningful and stable regardless of when we happen to
          // scan it.
          final deviceDateAdded = song.dateAdded;
          final createdAt = deviceDateAdded != null
              ? DateTime.fromMillisecondsSinceEpoch(deviceDateAdded * 1000)
              : now;

          final custom = nameOverrides[filePath];
          final track = Track()
            ..title = custom?['title'] ??
                (song.title.isNotEmpty ? song.title : 'Titre inconnu')
            ..artist = custom?['artist'] ??
                ((song.artist != null && song.artist!.isNotEmpty)
                    ? song.artist!
                    : 'Artiste inconnu')
            ..album = song.album
            ..filePath = filePath
            ..uri = song.uri
            ..duration = song.duration
            ..coverUrl = cachedArt
            ..createdAt = createdAt
            ..updatedAt = now;
          toSave.add(track);
        }
      }

      await TrackGenres.merge(genreByPath);

      final needsReload = toSave.isNotEmpty;
      if (needsReload) await _storageService.saveTracks(toSave);

      if (needsReload) {
        // La liste est peut-être déjà à l'écran : une seule mise à jour, et
        // jamais pendant un défilement. Relecture « silencieuse » (ids des
        // nouveaux morceaux, état « aimé »...), sans squelette.
        if (!initialLoad || shownFromCache) await UiGate.instance.idle();
        if (!mounted) return;
        await _reloadQuietly();
      } else if (state.tracks.isEmpty) {
        // Ouverture sans aucun changement : on réutilise la lecture de la
        // base déjà faite pour comparer, sans la refaire.
        state = state.copyWith(
          tracks: existingTracks,
          filteredTracks: existingTracks,
          isLoading: false,
        );
        _applyFilters();
      } else if (state.isLoading) {
        state = state.copyWith(isLoading: false);
      }

      // Extraction des pochettes manquantes en tâche de fond : le premier
      // scan d'une grosse bibliothèque prend un moment, et l'utilisateur
      // n'a aucune raison d'attendre devant une liste vide pour ça. Les
      // scans suivants ne repassent que sur les nouveautés.
      unawaited(_backfillArtwork(mediaStoreIdByPath, artCache));
    } catch (e) {
      // Whatever went wrong during the scan itself (permission plugin
      // hiccup, MediaStore query error, merge bug, etc.), don't leave the
      // screen showing an empty list when storage already has tracks from
      // a previous successful scan - fall back to those.
      try {
        if (state.tracks.isEmpty) await _reloadQuietly();
      } catch (_) {
        // Storage itself is also failing - nothing more we can recover.
      }
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors du scan de la bibliothèque. ${friendlyError(e)}',
      );
    } finally {
      loaderGuard?.cancel();
    }
  }

  /// Add a new track
  Future<void> addTrack(Track track) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _storageService.saveTrack(track);
      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de l\'ajout du morceau. ${friendlyError(e)}',
      );
    }
  }

  /// Updates a track's in-memory liked state to match a change that was
  /// already persisted elsewhere - the notification's own "like" button
  /// writes straight to storage (it doesn't have access to this
  /// provider), so this just reflects that change here without writing to
  /// storage again.
  void syncLikedFromExternal(int trackId, bool liked) {
    final index = state.tracks.indexWhere((t) => t.id == trackId);
    if (index == -1 || state.tracks[index].isLiked == liked) return;

    state.tracks[index].isLiked = liked;
    final updatedTracks = [...state.tracks];
    state = state.copyWith(tracks: updatedTracks);
    _applyFilters();
  }

  /// Sets [track]'s mood and confidence manually (from the player screen's
  /// mood-edit sheet), overriding whatever Groq classified it as. Marks it
  /// as classified with today's date so it won't be picked up again by
  /// [classifyAllUnclassified], and refreshes filtered lists so the track
  /// immediately moves out of its old mood section and into the new one.
  ///
  /// [secondaryMood] : ambiance secondaire choisie (null = aucune). Elle n'est
  /// touchée que si [updateSecondary] est vrai, pour que les appels qui ne
  /// parlent que de l'ambiance principale la laissent intacte. Une secondaire
  /// identique à la principale est ignorée.
  Future<void> setTrackMood(
    Track track, {
    required MoodType mood,
    required double confidence,
    MoodType? secondaryMood,
    bool updateSecondary = false,
  }) async {
    final previousMood = track.mood;
    final previousConfidence = track.moodConfidence;
    final previousSecondary = track.secondaryMood;

    track
      ..mood = mood
      ..moodConfidence = confidence.clamp(0.0, 1.0)
      ..lastClassified = DateTime.now()
      ..updatedAt = DateTime.now();

    if (updateSecondary) {
      track.secondaryMood =
          (secondaryMood == null || secondaryMood == MoodType.unknown)
              ? null
              : secondaryMood;
    }
    // La principale vient de devenir égale à l'ancienne secondaire : plus
    // de nuance à afficher.
    if (track.secondaryMood == mood) track.secondaryMood = null;

    try {
      await _storageService.saveTrack(track);
      await TrackSecondaryMoods.set(track.filePath, track.secondaryMood);
      // Mémorise la correction : elle servira d'exemple aux prochaines
      // classifications Groq (« ce que toi tu appelles chill »). Un échec
      // ici ne doit jamais empêcher le changement d'ambiance.
      if (previousMood != mood) {
        try {
          final genre = track.filePath != null
              ? (await TrackGenres.load())[track.filePath!]
              : null;
          await _correctionService?.record(track, mood, genre: genre);
        } catch (e) {
          debugPrint('[corrections] enregistrement impossible : $e');
        }
      }
      final updatedTracks = [
        for (final t in state.tracks) if (t.id == track.id) track else t,
      ];
      state = state.copyWith(tracks: updatedTracks, error: null);
      _applyFilters();
    } catch (e) {
      track
        ..mood = previousMood
        ..moodConfidence = previousConfidence
        ..secondaryMood = previousSecondary;
      state = state.copyWith(
        error: 'Erreur lors de la mise à jour de l\'ambiance. ${friendlyError(e)}',
      );
    }
  }

  /// Toggles the liked status of [track] and persists it, updating the
  /// in-memory state without a full library reload.
  Future<void> toggleLike(Track track) async {
    final newValue = !track.isLiked;
    track.isLiked = newValue;
    try {
      await _storageService.setTrackLiked(track.id, newValue);
      final updatedTracks = [
        for (final t in state.tracks) if (t.id == track.id) track else t,
      ];
      state = state.copyWith(tracks: updatedTracks);
      _applyFilters();
      onLikedChanged?.call(track.id, newValue);
    } catch (e) {
      track.isLiked = !newValue;
      state = state.copyWith(error: 'Erreur lors de la mise à jour du favori. ${friendlyError(e)}');
    }
  }

  final TrackFileService _fileService = TrackFileService();

  /// Renomme le morceau ET son fichier sur l'appareil. Renvoie null en
  /// cas de succès, sinon un message d'erreur affichable (le fichier n'a
  /// alors pas été modifié).
  Future<String?> renameTrack(
    Track track, {
    required String artist,
    required String title,
  }) async {
    final oldPath = track.filePath;
    try {
      final newPath =
          await _fileService.renameAudio(track, artist: artist, title: title);

      // Même objet modifié sur place, comme toggleLike : le lecteur et
      // les listes qui le tiennent déjà voient le nouveau nom.
      track
        ..title = title
        ..artist = artist
        ..filePath = newPath
        ..updatedAt = DateTime.now();
      await _storageService.saveTrack(track);
      await TrackNameOverrides.set(
        oldPath: oldPath,
        newPath: newPath,
        title: title,
        artist: artist,
      );
      await TrackSecondaryMoods.move(oldPath, newPath);

      state = state.copyWith(tracks: [
        for (final t in state.tracks) if (t.id == track.id) track else t,
      ]);
      _applyFilters();
      return null;
    } on TrackRenameException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erreur lors du renommage. ${friendlyError(e)}';
    }
  }

  /// Classify a single track (kept for completeness/manual use elsewhere -
  /// batch classification below is the path actually used for bulk work).
  Future<void> classifyTrack(Track track) async {
    if (track.isClassified) return;
    final doubtful = await _applyLocalClassification([track]);
    if (doubtful.isEmpty) return;
    await _classifyChunk(doubtful, maxRateLimitRetries: 5);
  }

  /// Classe localement, à partir du tag genre, les morceaux de [tracks] dont
  /// le genre désigne sans ambiguïté une ambiance, les enregistre, et
  /// renvoie les autres (les cas douteux, à envoyer à Groq).
  ///
  /// Un genre que l'utilisateur a déjà contredit en reclassant un morceau à
  /// la main n'est plus tranché localement : sa définition personnelle prime.
  Future<List<Track>> _applyLocalClassification(List<Track> tracks) async {
    try {
      final genres = await TrackGenres.load();
      if (genres.isEmpty) return tracks;

      final decided = <Track>[];
      final doubtful = <Track>[];
      final now = DateTime.now();

      // Calculés une seule fois pour toute la passe (et non par morceau) :
      // les ambiances déjà corrigées par genre, et le verdict par genre.
      final correctedMoods = await _correctionService?.moodsByGenre() ??
          const <String, Set<MoodType>>{};
      final guessByGenre = <String, GenreMoodGuess?>{};

      var seen = 0;
      for (final track in tracks) {
        if (++seen % 300 == 0) await Future<void>.delayed(Duration.zero);
        final genre = track.filePath != null ? genres[track.filePath!] : null;
        final guess = genre == null
            ? null
            : guessByGenre.putIfAbsent(
                genre, () => GenreMoodClassifier.guess(genre));
        final contested = guess != null &&
            genre != null &&
            (correctedMoods[genre.trim().toLowerCase()]
                    ?.any((m) => m != guess.mood) ??
                false);

        if (guess == null || contested) {
          doubtful.add(track);
          continue;
        }
        track
          ..mood = guess.mood
          ..moodConfidence = guess.confidence
          ..lastClassified = now;
        decided.add(track);
      }

      if (decided.isEmpty) return tracks;

      await _storageService.saveTracks(decided);
      final indexById = {
        for (var i = 0; i < state.tracks.length; i++) state.tracks[i].id: i,
      };
      final updatedTracks = List<Track>.from(state.tracks);
      for (final t in decided) {
        final i = indexById[t.id];
        if (i != null) updatedTracks[i] = t;
      }
      state = state.copyWith(tracks: updatedTracks);
      _applyFilters();
      return doubtful;
    } catch (e) {
      // Le pré-classement n'est qu'un raccourci : en cas de souci, tout part
      // chez Groq comme avant.
      debugPrint('[classification locale] ignorée : $e');
      return tracks;
    }
  }

  /// Sends one Groq request classifying every track in [chunk] together,
  /// applies the results, and retries the whole chunk automatically if
  /// Groq responds with a rate limit (429).
  Future<bool> _classifyChunk(
    List<Track> chunk, {
    required int maxRateLimitRetries,
    int maxNetworkRetries = 4,
  }) async {
    var attempt = 0;
    var networkAttempt = 0;
    while (true) {
      try {
        final corrections =
            await _correctionService?.examplesFor(chunk) ?? const <MoodCorrection>[];
        final results = await _groqService.classifyTracksBatch(
          chunk,
          corrections: corrections,
          genresByPath: await TrackGenres.load(),
        );

        final updatedTracks = List<Track>.from(state.tracks);
        String? lastError;
        final toSave = <Track>[];
        final secondaryByPath = <String, MoodType>{};
        final clearedSecondary = <String>[];

        for (var i = 0; i < chunk.length; i++) {
          final track = chunk[i];
          final result = results[i];

          if (!result.hasError) {
            track.mood = result.mood;
            track.moodConfidence = result.confidence;
            track.secondaryMood = result.secondaryMood;
            track.lastClassified = DateTime.now();
            toSave.add(track);
            final path = track.filePath;
            if (path != null) {
              final sec = result.secondaryMood;
              if (sec != null) {
                secondaryByPath[path] = sec;
              } else {
                clearedSecondary.add(path);
              }
            }

            final index = updatedTracks.indexWhere((t) => t.id == track.id);
            if (index != -1) updatedTracks[index] = track;
          } else {
            debugPrint('[erreur] classification "${track.title}" : ${result.error}');
            lastError = 'Impossible de classer « ${track.title} ». '
                'Il sera retenté à la prochaine classification.';
          }
        }

        if (toSave.isNotEmpty) {
          await _storageService.saveTracks(toSave);
          for (final path in clearedSecondary) {
            await TrackSecondaryMoods.remove(path);
          }
          await TrackSecondaryMoods.merge(secondaryByPath);
        }

        state = state.copyWith(
          tracks: updatedTracks,
          error: lastError,
        );
        _applyFilters();
        return true;
      } on GroqRateLimitException catch (e) {
        attempt++;
        if (attempt > maxRateLimitRetries) {
          state = state.copyWith(
            error: 'La classification est interrompue : trop de requêtes pour '
                'le moment. Relance-la dans quelques minutes, les morceaux '
                'déjà classés sont conservés.',
          );
          return false;
        }

        // Attente silencieuse : l'utilisateur ne voit que la progression
        // (ex. « 50 / 300 »), pas le détail de la limite de requêtes.
        await Future.delayed(
          Duration(seconds: e.retryAfter.inSeconds.clamp(1, 120)),
        );
        // loop back around and retry this same chunk
      } on GroqNetworkException {
        networkAttempt++;
        if (networkAttempt > maxNetworkRetries) {
          state = state.copyWith(
            error: 'Classification interrompue : connexion impossible. '
                'Vérifie ta connexion internet puis relance-la, les morceaux '
                'déjà classés sont conservés.',
          );
          return false;
        }

        // Exponential backoff (3s, 6s, 12s, 24s...) en silence.
        final waitSeconds = (3 * (1 << (networkAttempt - 1))).clamp(1, 30);
        await Future.delayed(Duration(seconds: waitSeconds));
        // loop back around and retry this same chunk
      } catch (e) {
        state = state.copyWith(
          error: 'Erreur lors de la classification du lot. ${friendlyError(e)}',
        );
        return false;
      }
    }
  }

  /// Classify all unclassified tracks, sent in batches (default 50 tracks
  /// per Groq request) instead of one request per track - cuts the number
  /// of API calls by ~50x, which matters a lot against free-tier rate
  /// limits when classifying a whole library.
  ///
  /// [limit] restreint la passe aux N premiers morceaux non classifiés
  /// (test rapide sur une très grosse bibliothèque).
  Future<void> classifyAllUnclassified({int batchSize = 50, int? limit}) async {
    // Évite de lancer deux classifications en parallèle (double tap).
    if (state.isClassifying) return;
    state = state.copyWith(error: null);

    try {
      var unclassifiedTracks = await _storageService.getUnclassifiedTracks();
      if (limit != null && unclassifiedTracks.length > limit) {
        unclassifiedTracks = unclassifiedTracks.sublist(0, limit);
      }
      if (unclassifiedTracks.isEmpty) return;

      state = state.copyWith(
        classifyProgress: 0,
        classifyTotal: unclassifiedTracks.length,
      );

      // Étape 1, instantanée et sans réseau : les morceaux dont le genre
      // tranche clairement (gospel, classique, métal...) sont classés tout
      // de suite. Seuls les cas douteux partent chez Groq : moins de
      // requêtes, moins de limite de débit, et une connexion faible n'empêche
      // plus d'avancer.
      final doubtful = await _applyLocalClassification(unclassifiedTracks);
      var processed = unclassifiedTracks.length - doubtful.length;
      state = state.copyWith(classifyProgress: processed);

      for (var start = 0; start < doubtful.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, doubtful.length);
        final chunk = doubtful.sublist(start, end);

        await UiGate.instance.idle();
        final completed = await _classifyChunk(chunk, maxRateLimitRetries: 5);
        // Échec définitif (réseau / limite de requêtes) : inutile d'enchaîner
        // les lots suivants, le message d'erreur est déjà affiché.
        if (!completed) break;
        processed += chunk.length;
        state = state.copyWith(classifyProgress: processed, error: state.error);

        // Small pause between batches - with 50 tracks/request there are
        // far fewer calls overall, but this still keeps us clear of
        // Groq's free-tier rate limit if batches are small/numerous.
        if (end < doubtful.length) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Erreur lors de la classification en lot. ${friendlyError(e)}',
      );
    } finally {
      // Always clear the progress indicator, whether every track
      // succeeded, some failed, or the whole batch blew up.
      state = state.copyWith(clearClassifyProgress: true);
    }
  }

  /// Filter tracks by mood
  void filterByMood(MoodType? mood) {
    state = state.copyWith(selectedMood: mood);
    _applyFilters();
  }

  /// Search tracks
  void searchTracks(String query) {
    state = state.copyWith(searchQuery: query);
    _applyFilters();
  }

  /// Change how the "Tous les morceaux" list is ordered
  void setSortOption(TrackSortOption option) {
    state = state.copyWith(sortOption: option);
    _applyFilters();
  }

  /// Hide tracks shorter than [seconds]. Pass null to remove the filter.
  void setMinDurationFilter(int? seconds) {
    _filterLoaded = true; // le choix explicite prime sur le fichier
    _filterService.saveMinDurationSeconds(
        seconds != null && seconds > 0 ? seconds : null);
    if (seconds == null) {
      state = state.copyWith(clearMinDurationSeconds: true);
    } else {
      state = state.copyWith(minDurationSeconds: seconds);
    }
    _applyFilters();
  }

  /// Apply current filters
  void _applyFilters() {
    List<Track> filtered = List.from(state.tracks);
    
    // Filter by mood
    if (state.selectedMood != null) {
      filtered = filtered.where((track) => track.mood == state.selectedMood).toList();
    }
    
    // Filter by search query
    if (state.searchQuery.isNotEmpty) {
      final query = state.searchQuery.toLowerCase();
      filtered = filtered.where((track) =>
        track.title.toLowerCase().contains(query) ||
        track.artist.toLowerCase().contains(query) ||
        (track.album?.toLowerCase().contains(query) ?? false)
      ).toList();
    }

    // Hide short tracks (e.g. ringtones/notification sounds picked up by
    // the device scan)
    final minSeconds = state.minDurationSeconds;
    if (minSeconds != null && minSeconds > 0) {
      final minMs = minSeconds * 1000;
      filtered = filtered
          .where((track) => (track.duration ?? 0) >= minMs)
          .toList();
    }

    // Sort
    switch (state.sortOption) {
      case TrackSortOption.nameAsc:
      case TrackSortOption.nameDesc:
        // Clés en minuscules calculées une seule fois (et non deux par
        // comparaison) : le tri d'une grosse bibliothèque est bien plus léger.
        final keys = Map<Track, String>.identity();
        for (final t in filtered) {
          keys[t] = t.title.toLowerCase();
        }
        final asc = state.sortOption == TrackSortOption.nameAsc;
        filtered.sort((a, b) =>
            asc ? keys[a]!.compareTo(keys[b]!) : keys[b]!.compareTo(keys[a]!));
        break;
      case TrackSortOption.dateNewest:
        filtered.sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
        break;
      case TrackSortOption.dateOldest:
        filtered.sort((a, b) => (a.createdAt ?? DateTime(0))
            .compareTo(b.createdAt ?? DateTime(0)));
        break;
    }
    
    state = state.copyWith(filteredTracks: filtered);
  }

  /// Delete a track
  Future<void> deleteTrack(int id) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      // Retient le chemin pour que le prochain scan ne rajoute pas le
      // morceau (son fichier est toujours sur l'appareil).
      final path = state.tracks.firstWhereOrNull((t) => t.id == id)?.filePath;
      if (path != null) await RemovedTracks.add(path);
      await TrackSecondaryMoods.remove(path);
      await _storageService.deleteTrack(id);
      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de la suppression. ${friendlyError(e)}',
      );
    }
  }

  /// Clear all tracks
  Future<void> clearAllTracks() async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _storageService.clearAllTracks();
      await RemovedTracks.clear();
      await TrackSecondaryMoods.clear();
      await loadTracks();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de la suppression. ${friendlyError(e)}',
      );
    }
  }
}

// Track provider
final trackProvider = StateNotifierProvider<TrackNotifier, TrackState>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  final groqService = ref.watch(groqServiceProvider);
  final libraryScanService = ref.watch(libraryScanServiceProvider);
  final artworkService = ref.watch(artworkServiceProvider);
  final correctionService = ref.watch(moodCorrectionServiceProvider);
  return TrackNotifier(
    storageService,
    groqService,
    libraryScanService,
    artworkService,
    correctionService: correctionService,
    onLikedChanged: (trackId, liked) {
      try {
        ref
            .read(audioHandlerProvider)
            .valueOrNull
            ?.syncLikedFromApp(trackId, liked);
      } catch (_) {
        // Pas de lecteur audio (tests, échec d'init) : rien à synchroniser.
      }
    },
  );
});

// Filtered tracks provider
final filteredTracksProvider = Provider<List<Track>>((ref) {
  final trackState = ref.watch(trackProvider);
  return trackState.filteredTracks;
});

// Tracks by mood provider
final tracksByMoodProvider = Provider.family<List<Track>, MoodType>((ref, mood) {
  final trackState = ref.watch(trackProvider);
  return trackState.tracks.where((track) => track.mood == mood).toList();
});

// Track count by mood provider
final trackCountByMoodProvider = Provider<Map<MoodType, int>>((ref) {
  final trackState = ref.watch(trackProvider);
  final counts = <MoodType, int>{};
  
  for (final mood in MoodType.values) {
    if (mood == MoodType.unknown) continue;
    counts[mood] = trackState.tracks.where((track) => track.mood == mood).length;
  }
  
  return counts;
});

// Current mood filter provider
final currentMoodFilterProvider = Provider<MoodType?>((ref) {
  return ref.watch(trackProvider).selectedMood;
});