import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import 'playback_stats_provider.dart';
import 'profile_provider.dart';
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

/// Ambiances par défaut de chaque moment - l'utilisateur peut les changer
/// (voir [periodMoodsProvider]).
Set<MoodType> defaultMoodsForPeriod(DayPeriod period) {
  switch (period) {
    case DayPeriod.morning:
      return {MoodType.chill, MoodType.motivating};
    case DayPeriod.midday:
      return {MoodType.energetic};
    case DayPeriod.evening:
      return {MoodType.chill};
  }
}

String labelForPeriod(DayPeriod period) {
  switch (period) {
    case DayPeriod.morning:
      return 'Matin';
    case DayPeriod.midday:
      return 'Midi';
    case DayPeriod.evening:
      return 'Soir';
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

/// Ambiances actives pour un moment : le choix de l'utilisateur s'il en a
/// fait un, sinon les valeurs par défaut.
final periodMoodsProvider =
    Provider.family<Set<MoodType>, DayPeriod>((ref, period) {
  final stored =
      ref.watch(profileProvider.select((p) => p.periodMoods))[period.name];
  if (stored == null) return defaultMoodsForPeriod(period);
  final moods = stored
      .map((name) => MoodType.values.where((m) => m.name == name))
      .expand((m) => m)
      .where((m) => m != MoodType.unknown)
      .toSet();
  return moods.isEmpty ? defaultMoodsForPeriod(period) : moods;
});

/// Une carte de suggestion : 20 morceaux mélangeant artistes préférés et
/// ambiances du moment.
class SuggestionMix {
  final DayPeriod period;
  final int number;
  final List<Track> tracks;

  const SuggestionMix({
    required this.period,
    required this.number,
    required this.tracks,
  });

  String get title => 'Mix $number';

  /// Les premiers artistes du mix, pour le sous-titre de la carte.
  String get artistsSummary {
    final seen = <String>[];
    for (final t in tracks) {
      if (!seen.contains(t.artist)) seen.add(t.artist);
      if (seen.length == 4) break;
    }
    return seen.join(', ');
  }
}

const int mixesPerPeriod = 5;
const int tracksPerMix = 20;

/// 5 mixes de 20 morceaux pour un moment de la journée.
///
/// Chaque mix prend environ la moitié de ses morceaux chez les artistes
/// préférés (choisis à l'onboarding + les plus écoutés), le reste chez les
/// autres artistes, tous filtrés par les ambiances du moment. Les morceaux
/// déjà utilisés dans un mix précédent passent en dernier pour que les 5
/// mixes se ressemblent le moins possible. Le tirage est initialisé par la
/// date et le moment : il reste stable quand on revient sur la page, et se
/// renouvelle chaque jour.
final periodMixesProvider =
    Provider.family<List<SuggestionMix>, DayPeriod>((ref, period) {
  final moods = ref.watch(periodMoodsProvider(period));
  final allTracks = ref.watch(trackProvider).tracks;
  final counts = ref.watch(playbackStatsProvider);
  final profileArtists = ref.watch(profileProvider.select((p) => p.favoriteArtists));

  final pool =
      allTracks.where((t) => t.mood != null && moods.contains(t.mood)).toList();
  if (pool.isEmpty) return const [];

  final playsByArtist = <String, int>{};
  for (final t in allTracks) {
    final plays = counts[t.id] ?? 0;
    if (plays > 0) {
      final key = t.artist.toLowerCase();
      playsByArtist[key] = (playsByArtist[key] ?? 0) + plays;
    }
  }
  final topListened = (playsByArtist.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(3)
      .map((e) => e.key);
  final favorites = <String>{
    ...profileArtists.map((a) => a.toLowerCase()),
    ...topListened,
  };

  final now = DateTime.now();
  final rng = Random(Object.hash(now.year, now.month, now.day, period.index));
  final usage = <int, int>{};

  List<Track> leastUsedFirst(Iterable<Track> source) {
    final keyed = [for (final t in source) (t, rng.nextDouble())];
    keyed.sort((a, b) {
      final byUsage = (usage[a.$1.id] ?? 0).compareTo(usage[b.$1.id] ?? 0);
      return byUsage != 0 ? byUsage : a.$2.compareTo(b.$2);
    });
    return [for (final k in keyed) k.$1];
  }

  bool isFavorite(Track t) => favorites.contains(t.artist.toLowerCase());

  // Avec très peu de morceaux, 5 mixes seraient quasi identiques.
  final mixCount = pool.length >= tracksPerMix ? mixesPerPeriod : 1;
  final mixes = <SuggestionMix>[];

  for (var i = 0; i < mixCount; i++) {
    final result = <Track>[];
    final ids = <int>{};
    void add(Track t) {
      if (result.length < tracksPerMix && ids.add(t.id)) result.add(t);
    }

    // 1) Artistes préférés : jusqu'à la moitié du mix.
    for (final t in leastUsedFirst(pool.where(isFavorite))) {
      if (result.length >= tracksPerMix ~/ 2) break;
      add(t);
    }

    // 2) Autres artistes, à tour de rôle pour qu'aucun ne domine.
    final byArtist = <String, List<Track>>{};
    for (final t in leastUsedFirst(pool.where((t) => !ids.contains(t.id)))) {
      if (!isFavorite(t)) byArtist.putIfAbsent(t.artist, () => []).add(t);
    }
    final groups = byArtist.values.toList()..shuffle(rng);
    for (var round = 0;
        result.length < tracksPerMix && groups.any((g) => round < g.length);
        round++) {
      for (final g in groups) {
        if (round < g.length) add(g[round]);
      }
    }

    // 3) Complète avec le reste (favoris supplémentaires, petites biblios).
    for (final t in leastUsedFirst(pool)) {
      add(t);
    }

    result.shuffle(rng);
    for (final t in result) {
      usage[t.id] = (usage[t.id] ?? 0) + 1;
    }
    mixes.add(SuggestionMix(period: period, number: i + 1, tracks: result));
  }
  return mixes;
});
