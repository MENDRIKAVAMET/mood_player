import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/lyrics_service.dart';
import 'excerpt_share_screen.dart';
import 'lyrics_share_screen.dart';

/// Point d'entrée commun du partage (écran de lecture et écran des paroles).
/// Paroles utilisables -> sélection de lignes ; sinon -> extrait vidéo.
Future<void> startTrackShare(BuildContext context, Track track) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final provider = lyricsProvider(lyricsKeyFor(track));
  final rootNavigator = Navigator.of(context, rootNavigator: true);

  // Petit indicateur modal pendant la récupération des paroles.
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  ));

  LyricsResult? lyrics;
  // Garde le provider (autoDispose) vivant pendant l'attente.
  final sub = container.listen<AsyncValue<LyricsResult>>(provider, (_, _) {});
  try {
    lyrics = await container
        .read(provider.future)
        .timeout(const Duration(seconds: 12));
  } catch (e) {
    debugPrint('[partage] paroles indisponibles : $e');
  } finally {
    sub.close();
    if (rootNavigator.mounted) rootNavigator.pop();
  }

  if (!context.mounted) return;

  final r = lyrics;
  final usable = r != null &&
      !r.instrumental &&
      (r.hasSynced || (r.plain != null && r.plain!.trim().isNotEmpty));

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => usable
          ? LyricsShareScreen(track: track, result: r)
          : ExcerptShareScreen(track: track, lyrics: r),
    ),
  );
}
