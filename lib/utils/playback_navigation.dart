import 'dart:math';

import 'package:flutter/material.dart';

import '../features/player/player_screen.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';

/// Ouvre le lecteur sur [track], avec [tracks] comme file de lecture.
///
/// Factorisé ici parce que quatre écrans (bibliothèque, pour vous, mood,
/// recherche) ont besoin exactement de la même transition et de la même
/// logique d'index — le dupliquer à chaque fois était la meilleure façon
/// de finir avec des files de lecture incohérentes selon l'écran.
void openPlayer(
  BuildContext context, {
  required Track track,
  required List<Track> tracks,
}) {
  final index = tracks.indexWhere((t) => t.id == track.id);

  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => PlayerScreen(
        track: track,
        tracks: tracks,
        initialIndex: index >= 0 ? index : 0,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: const Offset(0.0, 1.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: AppTheme.animPageTransition,
    ),
  );
}

/// Lance la liste dans l'ordre affiché, depuis le premier morceau.
void playAll(BuildContext context, List<Track> tracks) {
  if (tracks.isEmpty) return;
  openPlayer(context, track: tracks.first, tracks: tracks);
}

/// Lance la liste en aléatoire.
///
/// On mélange une *copie* de la liste et on lit à partir du début, plutôt
/// que d'activer le mode shuffle du lecteur : l'ordre affiché à l'écran
/// n'est pas touché, et la file de lecture correspond exactement à ce que
/// l'utilisateur entend.
void playShuffled(BuildContext context, List<Track> tracks) {
  if (tracks.isEmpty) return;
  final shuffled = List<Track>.from(tracks)..shuffle(Random());
  openPlayer(context, track: shuffled.first, tracks: shuffled);
}
