import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import 'playback_stats_provider.dart';
import 'profile_provider.dart';
import 'track_provider.dart';

/// Trois moments de la journée, chacun avec ses ambiances associées -
/// volontairement séparé de [suggestedMixesProvider] (celui basé sur
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

/// Une carte de mix : un titre, un sous-titre (moment de la journée pour les
/// mixes du moment, ou simple mention pour les mixes de suggestions), et ses
/// morceaux — 20 pour tous les mixes de l'app.
class TrackMix {
  final String title;
  final String subtitle;
  final List<Track> tracks;

  const TrackMix({
    required this.title,
    required this.subtitle,
    required this.tracks,
  });

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

/// Construit [mixCountWanted] mixes de [tracksPerMix] morceaux à partir de
/// [pool], en répartissant équitablement entre artistes « favoris »
/// (au sens de [isFavorite]) et les autres, avec un tirage aléatoire
/// [rng] et un anti-répétition entre mixes successifs (les morceaux déjà
/// utilisés dans un mix précédent passent en dernier). Factorisé entre
/// [periodMixesProvider] (ambiances du moment) et [suggestedMixesProvider]
/// (artistes préférés + historique d'écoute), qui ne diffèrent que par la
/// façon dont [pool] et [isFavorite] sont calculés.
List<List<Track>> _buildMixes({
  required List<Track> pool,
  required bool Function(Track track) isFavorite,
  required Random rng,
  required int mixCountWanted,
}) {
  if (pool.isEmpty) return const [];

  final usage = <int, int>{};

  List<Track> leastUsedFirst(Iterable<Track> source) {
    final keyed = [for (final t in source) (t, rng.nextDouble())];
    keyed.sort((a, b) {
      final byUsage = (usage[a.$1.id] ?? 0).compareTo(usage[b.$1.id] ?? 0);
      return byUsage != 0 ? byUsage : a.$2.compareTo(b.$2);
    });
    return [for (final k in keyed) k.$1];
  }

  // Avec très peu de morceaux, plusieurs mixes seraient quasi identiques.
  final mixCount = pool.length >= tracksPerMix ? mixCountWanted : 1;
  final mixes = <List<Track>>[];

  for (var i = 0; i < mixCount; i++) {
    final result = <Track>[];
    final ids = <int>{};
    void add(Track t) {
      if (result.length < tracksPerMix && ids.add(t.id)) result.add(t);
    }

    // 1) Artistes favoris : jusqu'à la moitié du mix.
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
    mixes.add(result);
  }
  return mixes;
}

/// 5 mixes de 20 morceaux pour un moment de la journée.
///
/// Chaque mix prend environ la moitié de ses morceaux chez les artistes
/// préférés (choisis à l'onboarding + les plus écoutés), le reste chez les
/// autres artistes, tous filtrés par les ambiances du moment. Le tirage est
/// initialisé par la date et le moment : il reste stable quand on revient
/// sur la page, et se renouvelle chaque jour.
final periodMixesProvider =
    Provider.family<List<TrackMix>, DayPeriod>((ref, period) {
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

  final mixes = _buildMixes(
    pool: pool,
    isFavorite: (t) => favorites.contains(t.artist.toLowerCase()),
    rng: rng,
    mixCountWanted: mixesPerPeriod,
  );
  return [
    for (var i = 0; i < mixes.length; i++)
      TrackMix(
        title: 'Mix ${i + 1}',
        subtitle: labelForPeriod(period),
        tracks: mixes[i],
      ),
  ];
});

/// 5 mixes de 20 morceaux tirés des artistes préférés, des morceaux
/// réellement écoutés et des morceaux aimés — le pendant « suggestions »
/// des mixes du moment ci-dessus, mais basé sur les habitudes de
/// l'utilisateur plutôt que sur l'heure qu'il est.
///
/// Pour un nouveau profil sans historique d'écoute, les 3 artistes
/// préférés choisis à l'onboarding servent de base : sans ça, cette
/// section resterait vide jusqu'à ce que l'utilisateur ait déjà écouté ou
/// aimé plusieurs morceaux, ce qui rend la question de l'onboarding
/// inutile en pratique.
final suggestedMixesProvider = Provider<List<TrackMix>>((ref) {
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

  final now = DateTime.now();
  final rng =
      Random(Object.hash(now.year, now.month, now.day, 'suggestions'));

  List<TrackMix> buildFrom(List<Track> pool, bool Function(Track) isFavorite) {
    final mixes = _buildMixes(
      pool: pool,
      isFavorite: isFavorite,
      rng: rng,
      mixCountWanted: mixesPerPeriod,
    );
    return [
      for (var i = 0; i < mixes.length; i++)
        TrackMix(
          title: 'Mix ${i + 1}',
          subtitle: 'D\'après tes goûts',
          tracks: mixes[i],
        ),
    ];
  }

  if (seeds.isEmpty) {
    if (favoriteArtists.isEmpty) return const [];
    // Cold start : rien écouté ni aimé pour le moment, mais des artistes
    // préférés existent - ce sont eux qui remplissent les mixes proposés,
    // plutôt qu'une section vide.
    final fromFavorites = allTracks
        .where((t) => favoriteArtists.contains(t.artist.toLowerCase()))
        .toList();
    return buildFrom(fromFavorites, (t) => true);
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

  // Pas assez de morceaux liés aux goûts de l'utilisateur pour remplir des
  // mixes entiers : on complète avec le reste de la bibliothèque plutôt
  // que de renvoyer des mixes tronqués.
  var pool = scored.map((e) => e.$1).toList();
  if (pool.length < tracksPerMix * mixesPerPeriod) {
    final poolIds = pool.map((t) => t.id).toSet();
    pool = [
      ...pool,
      ...candidates.where((t) => !poolIds.contains(t.id)),
    ];
  }
  if (pool.isEmpty) return const [];

  bool isFavorite(Track t) {
    final artist = t.artist.toLowerCase();
    return favoriteArtists.contains(artist) || (artistScores[artist] ?? 0) > 0;
  }

  return buildFrom(pool, isFavorite);
});
