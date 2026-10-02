import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../providers/track_provider.dart';
import '../../services/audio_handler.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/listen_reminder_host.dart';
import '../../widgets/mini_player.dart';
import '../foryou/for_you_screen.dart';
import '../library/library_screen.dart';
import '../mood/moods_screen.dart';

/// Coquille principale de l'app : trois onglets (Bibliothèque, Pour vous,
/// Ambiances) plus le mini-lecteur, partagé entre les trois.
///
/// Les onglets sont gardés vivants par un [IndexedStack] : changer
/// d'onglet ne relance pas un scan de la bibliothèque et ne fait pas
/// perdre la position de défilement.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  StreamSubscription<(int, bool)>? _likeChangedSub;
  bool _sessionRestoreAttempted = false;

  static const _navigationChannel =
      MethodChannel('com.example.mood_player/navigation');

  static const List<Widget> _screens = [
    LibraryScreen(),
    ForYouScreen(),
    MoodsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The notification's own "like" button persists straight to storage
    // (it has no access to Riverpod), so mirror that change into the
    // track list/player state here - this is the one widget that's
    // guaranteed to live for the whole app session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(audioHandlerProvider).whenData((handler) {
        _likeChangedSub = handler.likeChangedStream.listen((event) {
          final (trackId, liked) = event;
          ref.read(trackProvider.notifier).syncLikedFromExternal(trackId, liked);
        });
      });
    });

    // Instancie le contrôleur de lecture intelligente pour toute la durée
    // de vie de l'app - MainShell est le seul widget garanti de rester
    // monté en permanence (voir commentaire au-dessus).
    ref.read(smartQueueControllerProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _likeChangedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Filet de sécurité en plus de la sauvegarde périodique et de celle
    // déclenchée par `pause()` : capture l'état dès que l'app passe en
    // arrière-plan, juste avant le moment où MIUI/EMUI est le plus
    // susceptible de tuer le processus.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(audioHandlerProvider).whenData((h) => h.persistPlaybackState());
    }
  }

  /// Au premier lancement après un redémarrage du processus, recharge le
  /// morceau et la position sauvegardés (voir `persistPlaybackState` /
  /// `onTaskRemoved` dans [MoodAudioHandler]) - sans démarrer la lecture,
  /// l'utilisateur la relance lui-même.
  Future<void> _maybeRestoreSession(TrackState trackState) async {
    if (_sessionRestoreAttempted || trackState.isLoading) return;
    _sessionRestoreAttempted = true;
    if (trackState.tracks.isEmpty) return;

    final saved = await StorageService().loadLastPlaybackState();
    if (saved == null) return;

    try {
      final rawIds = saved['trackIds'] as List<dynamic>?;
      final index = saved['index'] as int?;
      final positionMs = saved['positionMs'] as int?;
      if (rawIds == null || index == null || positionMs == null) return;
      if (index < 0 || index >= rawIds.length) return;

      final byId = {for (final t in trackState.tracks) t.id: t};
      final restoredTracks = [
        for (final id in rawIds) byId[id as int],
      ];
      // Un morceau supprimé depuis la dernière session ferait planter la
      // reprise à un mauvais index : on renonce plutôt que de deviner.
      if (restoredTracks.any((t) => t == null)) return;

      final handler = await ref.read(audioHandlerProvider.future);
      await handler.restoreSession(
        tracks: restoredTracks.cast<Track>(),
        index: index,
        position: Duration(milliseconds: positionMs),
        shuffle: saved['shuffle'] as bool? ?? false,
        repeatMode: PlayerRepeatMode.values.firstWhere(
          (m) => m.name == saved['repeatMode'],
          orElse: () => PlayerRepeatMode.off,
        ),
      );
    } catch (_) {
      // Pas grave : l'utilisateur repart juste sans reprise.
    }
  }

  /// Renvoie la tâche en arrière-plan (comme le bouton Accueil) au lieu
  /// de laisser le bouton retour tuer l'app depuis cet écran racine.
  Future<void> _moveToBackground() async {
    try {
      await _navigationChannel.invokeMethod('moveTaskToBack');
    } catch (_) {
      // Si l'appel natif échoue pour une raison ou une autre, mieux vaut
      // ne rien faire (l'app reste ouverte) que risquer une fermeture
      // brutale non maîtrisée.
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final mediaItem = currentTrack.valueOrNull;

    ref.listen(trackProvider, (previous, next) => _maybeRestoreSession(next));

    return PopScope(
      // MainShell est la racine de l'app : il n'y a rien "en dessous" à
      // afficher si on laisse le pop se faire, ça fermerait l'app. On
      // intercepte donc systématiquement et on redirige vers un simple
      // retour en arrière-plan.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _moveToBackground();
      },
      child: Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _screens),

          // Pop-up « tu écoutais ça à cette heure » (invisible sinon).
          const ListenReminderHost(),

          // Mini-lecteur posé juste au-dessus de la barre d'onglets, quel
          // que soit l'onglet affiché.
          if (mediaItem != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayer(currentTrack: _mediaItemToTrack(mediaItem)),
            ),
        ],
      ),
      // Barre translucide posée sur un léger voile de marque plutôt qu'un
      // aplat opaque : le dégradé de l'écran continue derrière elle.
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x005D00FF), Color(0x335D00FF)],
          ),
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i != _index) HapticFeedback.selectionClick();
            setState(() => _index = i);
          },
          backgroundColor: Colors.transparent,
          indicatorColor: AppTheme.accentPrimary.withValues(alpha: 0.22),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded, color: AppTheme.accentPrimary),
              label: 'Bibliothèque',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded, color: AppTheme.accentPrimary),
              label: 'Pour vous',
            ),
            NavigationDestination(
              icon: Icon(Icons.graphic_eq_outlined),
              selectedIcon: Icon(Icons.graphic_eq_rounded, color: AppTheme.accentPrimary),
              label: 'Ambiances',
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Convertit un MediaItem du service audio en Track pour l'UI.
  Track _mediaItemToTrack(MediaItem item) {
    return Track()
      ..id = int.tryParse(item.id) ?? 0
      ..title = item.title
      ..artist = item.artist ?? 'Artiste inconnu'
      ..album = (item.album?.isNotEmpty ?? false) ? item.album : null
      ..filePath = item.extras?['filePath'] as String?
      ..coverUrl = item.extras?['coverUrl'] as String?
      ..moodIndex = item.extras?['mood'] != null
          ? MoodTypeExtension.fromString(item.extras!['mood'] as String).index
          : null
      ..moodConfidence = (item.extras?['moodConfidence'] as num?)?.toDouble();
  }
}
