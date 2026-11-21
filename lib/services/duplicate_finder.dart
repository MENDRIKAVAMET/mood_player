import '../models/track.dart';

/// Un groupe de morceaux qui sont (très probablement) le même titre en
/// plusieurs exemplaires dans la bibliothèque.
///
/// [tracks] est trié : le premier est l'exemplaire conseillé à garder.
class DuplicateGroup {
  final List<Track> tracks;

  const DuplicateGroup(this.tracks);

  Track get suggestedKeeper => tracks.first;

  /// Nombre d'exemplaires en trop si on n'en garde qu'un.
  int get extraCount => tracks.length - 1;
}

/// Ce que l'utilisateur a décidé pour un groupe : on garde [keeper], on
/// retire [removed] de la bibliothèque (les fichiers ne sont pas effacés).
class DuplicateResolution {
  final Track keeper;
  final List<Track> removed;

  const DuplicateResolution({required this.keeper, required this.removed});
}

/// Détection de doublons dans la bibliothèque.
///
/// Deux morceaux sont des doublons quand leur titre ET leur artiste sont
/// identiques une fois « nettoyés » (casse, accents, ponctuation, mentions
/// du genre « (Official Video) », « feat. X », « - Copy »…) ET que leurs
/// durées sont proches (à [durationToleranceMs] près), ce qui évite de
/// confondre une version live ou un remix avec l'original.
class DuplicateFinder {
  DuplicateFinder._();

  /// Écart de durée toléré entre deux exemplaires (2 secondes).
  static const int durationToleranceMs = 2000;

  static List<DuplicateGroup> find(List<Track> tracks) {
    final byKey = <String, List<Track>>{};
    for (final t in tracks) {
      final title = normalizeTitle(t.title);
      if (title.isEmpty) continue;
      final key = '$title|${normalizeArtist(t.artist)}';
      byKey.putIfAbsent(key, () => []).add(t);
    }

    final groups = <DuplicateGroup>[];
    for (final candidates in byKey.values) {
      if (candidates.length < 2) continue;
      for (final cluster in _clusterByDuration(candidates)) {
        if (cluster.length < 2) continue;
        cluster.sort(_compareKeepPriority);
        groups.add(DuplicateGroup(cluster));
      }
    }

    // Les groupes avec le plus d'exemplaires d'abord, puis par titre.
    groups.sort((a, b) {
      final byCount = b.tracks.length.compareTo(a.tracks.length);
      if (byCount != 0) return byCount;
      return a.suggestedKeeper.title
          .toLowerCase()
          .compareTo(b.suggestedKeeper.title.toLowerCase());
    });
    return groups;
  }

  /// Regroupe les morceaux de durées proches. Ceux dont la durée est
  /// inconnue ne sont jamais mélangés à ceux qui en ont une : on préfère
  /// rater un doublon que proposer d'en retirer un faux.
  static List<List<Track>> _clusterByDuration(List<Track> tracks) {
    final known = tracks.where((t) => (t.duration ?? 0) > 0).toList()
      ..sort((a, b) => a.duration!.compareTo(b.duration!));
    final unknown = tracks.where((t) => (t.duration ?? 0) <= 0).toList();

    final clusters = <List<Track>>[];
    for (final t in known) {
      if (clusters.isNotEmpty &&
          t.duration! - clusters.last.last.duration! <= durationToleranceMs) {
        clusters.last.add(t);
      } else {
        clusters.add([t]);
      }
    }
    if (unknown.length > 1) clusters.add(unknown);
    return clusters;
  }

  /// Exemplaire à garder en premier : favori, déjà classé par ambiance,
  /// avec une ambiance secondaire, hors dossiers « jetables » (messageries,
  /// téléchargements), puis le plus ancien.
  static int _compareKeepPriority(Track a, Track b) {
    final byScore = _keepScore(b).compareTo(_keepScore(a));
    if (byScore != 0) return byScore;
    final byDate = (a.createdAt ?? DateTime(9999))
        .compareTo(b.createdAt ?? DateTime(9999));
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  }

  static int _keepScore(Track t) {
    var score = 0;
    if (t.isLiked) score += 8;
    if (t.isClassified && t.mood != MoodType.unknown) score += 4;
    if (t.effectiveSecondaryMood != null) score += 1;
    if (_isThrowawayFolder(t.filePath)) score -= 2;
    return score;
  }

  static bool _isThrowawayFolder(String? path) {
    if (path == null) return false;
    final p = path.toLowerCase();
    return p.contains('/whatsapp/') ||
        p.contains('/telegram/') ||
        p.contains('/download');
  }

  // ---------------------------------------------------------------------
  // Normalisation
  // ---------------------------------------------------------------------

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'œ': 'oe', 'æ': 'ae',
  };

  static String _fold(String input) {
    final lower = input.toLowerCase();
    final b = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      b.write(_accents[ch] ?? ch);
    }
    return b.toString();
  }

  static final _brackets = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
  static final _featuring =
      RegExp(r'\b(feat|ft|featuring)\b\.?.*$');
  static final _noise = RegExp(
    r'\b(official|officiel|video|clip|audio|lyrics?|paroles|hd|hq|4k|'
    r'remastered|remaster|copy|copie)\b',
  );
  static final _leadingNumber = RegExp(r'^\d{1,3}\s*[-._)]\s*');
  static final _nonAlnum = RegExp(r'[^a-z0-9]+');

  /// Titre ramené à une forme comparable. Vide si rien d'exploitable.
  static String normalizeTitle(String title) {
    var s = _fold(title);
    s = s.replaceAll(_brackets, ' ');
    s = s.replaceAll(_leadingNumber, '');
    s = s.replaceAll(_featuring, ' ');
    s = s.replaceAll(_noise, ' ');
    s = s.replaceAll(_nonAlnum, ' ').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.isNotEmpty) return s;
    // Titre fait uniquement de ponctuation/mentions : on retombe sur la
    // version simplement nettoyée plutôt que de tout regrouper.
    return _fold(title).replaceAll(_nonAlnum, ' ').trim();
  }

  /// Artiste ramené à une forme comparable ; vide si inconnu.
  static String normalizeArtist(String artist) {
    var s = _fold(artist);
    s = s.replaceAll(_brackets, ' ');
    s = s.replaceAll(_nonAlnum, ' ').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s == 'unknown' ||
        s == 'unknown artist' ||
        s == 'inconnu' ||
        s == 'artiste inconnu' ||
        s == 'various artists') {
      return '';
    }
    return s;
  }
}
