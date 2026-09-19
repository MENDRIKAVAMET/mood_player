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

/// Émet une valeur toutes les 15 minutes, juste pour forcer un
/// réexamen périodique de l'heure - [dayPeriodProvider] ne notifie ses
/// dépendants que lorsque la période elle-même change réellement (Riverpod
/// ne republie pas une valeur d'enum identique), donc ce tic ne provoque
/// pas un réordonnancement des suggestions toutes les 15 minutes, juste
/// une vérification.
final _clockTickProvider = StreamProvider<void>((ref) async* {
  yield null;
  await for (final _ in Stream<void>.periodic(const Duration(minutes: 15))) {
    yield null;
  }
});

final dayPeriodProvider = Provider<DayPeriod>((ref) {
  ref.watch(_clockTickProvider);
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
