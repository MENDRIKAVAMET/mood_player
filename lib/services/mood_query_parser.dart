import '../models/track.dart';

/// Ce que l'app a compris d'une phrase comme « un truc calme pour réviser » :
/// des ambiances pondérées (1.0 = la plus pertinente), et celles à éviter
/// (« pas triste »).
class MoodQuery {
  /// Poids par ambiance, entre 0 et 1, le plus fort valant 1.
  final Map<MoodType, double> weights;

  /// Ambiances explicitement écartées (« pas triste », « sans colère »).
  final Set<MoodType> excluded;

  /// D'où vient l'interprétation : mots-clés locaux ou Groq.
  final bool fromAi;

  const MoodQuery({
    this.weights = const {},
    this.excluded = const {},
    this.fromAi = false,
  });

  static const MoodQuery empty = MoodQuery();

  bool get hasMoods => weights.isNotEmpty;

  /// Vrai si la phrase écarte des ambiances (« pas triste »). Une recherche
  /// peut n'avoir QUE des exclusions : on renvoie alors tout ce qui est
  /// classé, sauf ces ambiances.
  bool get hasExclusions => excluded.isNotEmpty;

  /// Ambiances triées de la plus à la moins pertinente.
  List<MoodType> get ranked {
    final list = weights.keys.toList()
      ..sort((a, b) => weights[b]!.compareTo(weights[a]!));
    return list;
  }

  /// Version qui ne garde que les ambiances de [keep] (l'utilisateur peut
  /// décocher une puce).
  MoodQuery only(Set<MoodType> keep) => MoodQuery(
        weights: {
          for (final e in weights.entries)
            if (keep.contains(e.key)) e.key: e.value,
        },
        excluded: excluded,
        fromAi: fromAi,
      );

  /// Pertinence de [track] pour cette recherche (0 = hors sujet). L'ambiance
  /// principale compte plein, la secondaire à 60 % : un morceau
  /// « Chill + Nostalgique » répond à « un truc nostalgique ».
  double scoreTrack(Track track) {
    final primary = track.mood;
    if (primary != null && excluded.contains(primary)) return 0;

    var score = 0.0;
    if (primary != null) score += weights[primary] ?? 0;
    final secondary = track.effectiveSecondaryMood;
    if (secondary != null && !excluded.contains(secondary)) {
      score += (weights[secondary] ?? 0) * 0.6;
    }
    if (score <= 0) return 0;

    // Départage les ex æquo : un classement sûr passe devant un doute.
    final conf = (track.moodConfidence ?? 0.5).clamp(0.0, 1.0);
    return score * (0.85 + 0.15 * conf);
  }

  /// Morceaux de [tracks] qui répondent à la recherche, les plus pertinents
  /// d'abord.
  List<Track> rank(Iterable<Track> tracks) {
    if (weights.isEmpty) {
      return excluded.isEmpty ? const [] : _rankByExclusion(tracks);
    }
    final scored = <(Track, double)>[];
    for (final t in tracks) {
      final s = scoreTrack(t);
      if (s > 0) scored.add((t, s));
    }
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : a.$1.title.compareTo(b.$1.title);
    });
    return [for (final e in scored) e.$1];
  }

  /// Recherche purement négative (« pas triste ») : les morceaux classés dont
  /// ni l'ambiance principale ni la secondaire n'est écartée, par titre.
  /// Les morceaux sans ambiance sont laissés de côté : on ne peut pas
  /// affirmer qu'ils ne sont pas tristes.
  List<Track> _rankByExclusion(Iterable<Track> tracks) {
    final kept = <Track>[];
    for (final t in tracks) {
      final primary = t.mood;
      if (primary == null || excluded.contains(primary)) continue;
      final secondary = t.effectiveSecondaryMood;
      if (secondary != null && excluded.contains(secondary)) continue;
      kept.add(t);
    }
    kept.sort((a, b) => a.title.compareTo(b.title));
    return kept;
  }
}

class _Rule {
  /// Racines normalisées (sans accents, minuscules). Un mot du texte
  /// correspond s'il COMMENCE par la racine (« revis » ↔ réviser, révisions) ;
  /// une racine de 3 lettres ou moins doit être le mot entier. Une racine à
  /// espace est une expression.
  final List<String> stems;
  final Map<MoodType, double> weights;
  const _Rule(this.stems, this.weights);
}

/// Traduit une phrase libre en ambiances, localement et sans réseau.
/// Volontairement simple : un dictionnaire de racines FR/EN, un peu de
/// négation. Les formulations qu'il ne comprend pas sont renvoyées à Groq.
class MoodQueryParser {
  MoodQueryParser._();

  static const _c = MoodType.chill;
  static const _e = MoodType.energetic;

  static const List<_Rule> _rules = [
    // Détente
    _Rule(
      ['calme', 'tranquill', 'detend', 'relax', 'chill', 'paisible', 'apais',
       'cocon', 'se poser', 'calm', 'mellow', 'soft', 'doux', 'douce',
       'se reposer', 'repos'],
      {_c: 1.0, MoodType.concentration: 0.4, MoodType.sleep: 0.2},
    ),
    // Travail / études
    _Rule(
      ['revis', 'etud', 'bosse', 'bosser', 'travail', 'concentr', 'focus',
       'devoir', 'examen', 'partiel', 'lecture', 'lire', 'coder', 'programm',
       'study', 'homework', 'lofi', 'lo fi', 'instrumental', 'sans paroles',
       'sans parole', 'sans chant'],
      {MoodType.concentration: 1.0, MoodType.classical: 0.3, _c: 0.2},
    ),
    // Sport / effort
    _Rule(
      ['sport', 'muscu', 'gym', 'courir', 'course', 'footing', 'running',
       'workout', 'fitness', 'cardio', 'hiit', 'entrainement', 'entrain',
       'training', 'pump'],
      {_e: 1.0, MoodType.motivating: 0.7, MoodType.angry: 0.15},
    ),
    _Rule(
      ['energi', 'dynamique', 'booster', 'reveil', 'peps', 'energy', 'upbeat'],
      {_e: 1.0, MoodType.motivating: 0.4},
    ),
    _Rule(
      ['motiv', 'courage', 'se depasser', 'ambition', 'victoire', 'gagner',
       'reussir', 'perseverance', 'determin', 'boost'],
      {MoodType.motivating: 1.0, _e: 0.4},
    ),
    // Fête
    _Rule(
      ['fete', 'soiree', 'party', 'anniversaire', 'mariage', 'nouvel an',
       'apero', 'boite de nuit', 'club', 'entre amis', 'barbecue', 'danser',
       'danse', 'dance'],
      {MoodType.festive: 1.0, _e: 0.5},
    ),
    // Romantique
    _Rule(
      ['amour', 'romant', 'amoureux', 'valentin', 'chandelle', 'couple',
       'seduc', 'tendresse', 'intime', 'love'],
      {MoodType.romantic: 1.0, _c: 0.3},
    ),
    // Émotions
    _Rule(
      ['melanc', 'pensif', 'pluie', 'pluvieux', 'automne',
       'rainy'],
      {MoodType.melancholic: 1.0, MoodType.sad: 0.3, _c: 0.3},
    ),
    _Rule(
      ['triste', 'pleur', 'chagrin', 'deprim', 'rupture', 'larme', 'cafard',
       'blues', 'peine', 'sad', 'cry', 'heartbreak', 'coeur brise',
       'pas le moral'],
      {MoodType.sad: 1.0, MoodType.melancholic: 0.5},
    ),
    _Rule(
      ['priere', 'prier', 'louange', 'adorat', 'worship', 'gospel', 'eglise',
       'culte', 'dieu', 'jesus', 'seigneur', 'chretien', 'cantique', 'gloire',
       'praise'],
      {MoodType.evangelical: 1.0, MoodType.spiritual: 0.2},
    ),
    _Rule(
      ['colere', 'enerve', 'rage', 'furieux', 'defoul', 'frustr', 'metal',
       'punk', 'drill', 'angry', 'furious', 'agress'],
      {MoodType.angry: 1.0, _e: 0.3},
    ),
    _Rule(
      ['nostalg', 'souvenir', 'enfance', 'vintage', 'retro', 'autrefois',
       'bon vieux temps', 'vieux tube', 'ado', 'throwback', 'old school',
       'oldies'],
      {MoodType.nostalgic: 1.0, MoodType.melancholic: 0.3},
    ),
    _Rule(
      ['sombre', 'dark', 'tension', 'thriller', 'mysterieu', 'inquiet',
       'angoiss', 'halloween', 'creepy', 'cinematique', 'pesant'],
      {MoodType.dark: 1.0, MoodType.melancholic: 0.2},
    ),
    // Sommeil
    _Rule(
      ['dorm', 'endorm', 'sommeil', 'se coucher', 'berceuse', 'insomni',
       'sleep', 'bedtime', 'lullaby'],
      {MoodType.sleep: 1.0, _c: 0.4},
    ),
    // Humour
    _Rule(
      ['drole', 'rire', 'humour', 'parod', 'marrant', 'delire', 'blague',
       'funny', 'fou rire', 'comique'],
      {MoodType.funny: 1.0, MoodType.festive: 0.2},
    ),
    // Route
    _Rule(
      ['trajet', 'route', 'voiture', 'voyage', 'roadtrip', 'road trip',
       'conduire', 'conduite', 'autoroute', 'vacances', 'driving', 'drive',
       'bus', 'avion', 'balade'],
      {MoodType.roadtrip: 1.0, _e: 0.25, _c: 0.2},
    ),
    // Spiritualité hors christianisme
    _Rule(
      ['medit', 'yoga', 'pleine conscience', 'spirit', 'bols chantants',
       'chakra', 'mantra', 'zen', 'relaxation', 'tibetain'],
      {MoodType.spiritual: 1.0, _c: 0.4},
    ),
    // Classique
    _Rule(
      ['classique', 'classical', 'piano', 'orchestr', 'symphon', 'violon',
       'opera', 'baroque', 'mozart', 'beethoven', 'bach', 'chopin',
       'concerto', 'sonate'],
      {MoodType.classical: 1.0, MoodType.concentration: 0.3},
    ),
  ];

  static final RegExp _alnum = RegExp(r'[a-z0-9]');

  /// « années 80 », « années 2000 »… : toujours nostalgique.
  static final RegExp _decade =
      RegExp(r'\b(annees?|decennie|years?)\s+(19)?([5-9]0|2000|2010)\b');

  /// Mots qui inversent le sens du mot-clé qui les suit (« pas triste »).
  static const Set<String> _negators = {
    'pas', 'sans', 'ni', 'jamais', 'eviter', 'evite', 'not', 'no', 'without',
    'non',
  };

  /// Mots qui coupent la portée d'une négation (« sans paroles POUR réviser »).
  static const Set<String> _boundaries = {
    'pour', 'et', 'mais', 'avec', 'ou', 'puis', 'for', 'and', 'but', 'with',
  };

  /// Minuscules, sans accents, ponctuation → espace.
  static String normalize(String input) {
    const from = 'àâäáãåéèêëíìîïóòôöõúùûüýÿçñœæ';
    const to = 'aaaaaaeeeeiiiiooooouuuuyycnoa';
    final b = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      if (i >= 0) {
        b.write(to[i]);
        if (ch == 'œ') b.write('e');
        if (ch == 'æ') b.write('e');
      } else if (_alnum.hasMatch(ch)) {
        b.write(ch);
      } else {
        b.write(' ');
      }
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _tokenMatches(String token, String stem) =>
      stem.length <= 3 ? token == stem : token.startsWith(stem);

  /// « doux amer », « douce amertume » : une seule idée (mélancolie). Sans
  /// ce remplacement, « doux » déclenchait aussi la règle « calme ».
  static final RegExp _bittersweet = RegExp(r'\bdou(?:x|ce) amer\w*');

  /// Analyse [query]. Renvoie [MoodQuery.empty] si rien n'est reconnu.
  static MoodQuery parse(String query) {
    final norm = normalize(query).replaceAll(_bittersweet, 'melancolique');
    if (norm.isEmpty) return MoodQuery.empty;
    final tokens = norm.split(' ');
    final padded = ' $norm ';

    final sums = <MoodType, double>{};
    final excluded = <MoodType>{};

    void apply(_Rule rule, {required bool negated}) {
      if (negated) {
        rule.weights.forEach((mood, w) {
          if (w >= 0.5) excluded.add(mood);
        });
      } else {
        rule.weights.forEach((mood, w) {
          sums[mood] = (sums[mood] ?? 0) + w;
        });
      }
    }

    bool isNegated(int tokenIndex) {
      for (var back = 1; back <= 2; back++) {
        final j = tokenIndex - back;
        if (j < 0) return false;
        final t = tokens[j];
        if (_boundaries.contains(t)) return false;
        if (_negators.contains(t)) return true;
      }
      return false;
    }

    for (final rule in _rules) {
      var matchedPhrase = false;
      var matchedTokenIndex = -1;

      for (final stem in rule.stems) {
        if (stem.contains(' ')) {
          if (padded.contains(' $stem')) matchedPhrase = true;
          continue;
        }
        for (var i = 0; i < tokens.length; i++) {
          if (_tokenMatches(tokens[i], stem)) {
            matchedTokenIndex = i;
            break;
          }
        }
        if (matchedTokenIndex >= 0) break;
      }

      if (matchedTokenIndex >= 0) {
        apply(rule, negated: isNegated(matchedTokenIndex));
      } else if (matchedPhrase) {
        apply(rule, negated: false);
      }
    }

    if (_decade.hasMatch(norm)) {
      sums[MoodType.nostalgic] = (sums[MoodType.nostalgic] ?? 0) + 1.0;
      sums[MoodType.melancholic] = (sums[MoodType.melancholic] ?? 0) + 0.3;
    }

    for (final m in excluded) {
      sums.remove(m);
    }
    if (sums.isEmpty) return MoodQuery(excluded: excluded);

    final maxW = sums.values.reduce((a, b) => a > b ? a : b);
    return MoodQuery(
      weights: {
        for (final e in sums.entries)
          // Les poids très faibles seraient du bruit.
          if (e.value / maxW >= 0.2) e.key: e.value / maxW,
      },
      excluded: excluded,
    );
  }
}
