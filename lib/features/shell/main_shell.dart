import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
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

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const List<Widget> _screens = [
    LibraryScreen(),
    ForYouScreen(),
    MoodsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final mediaItem = currentTrack.valueOrNull;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _screens),

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
          onDestinationSelected: (i) => setState(() => _index = i),
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
      ..moodIndex = item.extras?['mood'] != null
          ? MoodTypeExtension.fromString(item.extras!['mood'] as String).index
          : null
      ..moodConfidence = (item.extras?['moodConfidence'] as num?)?.toDouble();
  }
}
