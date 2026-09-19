import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import 'track_provider.dart';

/// Trois moments de la journée, chacun avec ses ambiances associées -
/// volontairement séparé de [suggestedTracksProvider] (celui basé sur
/// l'historique d'écoute et les artistes préférés) : ici ça tourne sur
/// l'heure qu'il est, pas sur ce que l'utilisateur a déjà écouté, donc ça
/// change plusieurs fois dans la même journée même sans nouvelle écoute.
enum DayPeriod { morning, midday, evening }

DayPeriod _periodForHour(int hour) {
  if (hour >= 5 && hour < 12) return DayPeriod.morning;
  if (hour >= 12 && hour < 18) return DayPeriod.midday;
  return DayPeriod.evening;
}

Set<MoodType> _moodsForPeriod(DayPeriod period) {
  switch (period) {
    case DayPeriod.morning:
      // Calme pour démarrer en douceur, motivant pour lancer la journée.
      return {MoodType.chill, MoodType.motivating};
    case DayPeriod.midday:
      // Énergique et festif pour le coup de boost de milieu de journée.
      return {MoodType.energetic, MoodType.festive};
    case DayPeriod.evening:
      // Calme pour redescendre en fin de journée.
      return {MoodType.chill};
  }
}

String titleForPeriod(DayPeriod period) {
  switch (period) {
    case DayPeriod.morning:
      return 'Pour bien commencer la journée';
    case DayPeriod.midday:
      return 'Pour garder l\'énergie';
    case DayPeriod.evening:
      return 'Pour se poser ce soir';
  }
}

/// Se recalcule toutes les 15 minutes via [Timer.periodic], annulé
/// explicitement par [Ref.onDispose] - contrairement à un
/// `Stream.periodic` dont l'annulation dépend du moment où la
/// souscription sous-jacente est fermée, `ref.invalidateSelf()`
/// garantit qu'un nouveau timer est créé et l'ancien annulé de façon
/// synchrone et déterministe à chaque recalcul, y compris quand le
/// provider est détruit (tests, changement d'écran).
final dayPeriodProvider = Provider<DayPeriod>((ref) {
  final timer = Timer.periodic(const Duration(minutes: 15), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  return _periodForHour(DateTime.now().hour);
});

/// 20 morceaux mélangés entre artistes, filtrés par les ambiances du
/// moment de la journée. Le mélange par artiste (round-robin plutôt
/// qu'un simple shuffle global) évite qu'un artiste très présent dans la
/// bibliothèque monopolise la liste.
final timeBasedSuggestionsProvider = Provider<List<Track>>((ref) {
  final period = ref.watch(dayPeriodProvider);
  final moods = _moodsForPeriod(period);
  final allTracks = ref.watch(trackProvider).tracks;

  final matching =
      allTracks.where((t) => t.mood != null && moods.contains(t.mood)).toList()
        ..shuffle();
  if (matching.isEmpty) return const [];

  final byArtist = <String, List<Track>>{};
  for (final track in matching) {
    byArtist.putIfAbsent(track.artist, () => []).add(track);
  }
  final artistGroups = byArtist.values.toList()..shuffle();

  final result = <Track>[];
  var index = 0;
  while (result.length < 20 && artistGroups.any((g) => index < g.length)) {
    for (final group in artistGroups) {
      if (index < group.length) {
        result.add(group[index]);
        if (result.length >= 20) break;
      }
    }
    index++;
  }
  return result;
});
