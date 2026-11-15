import '../models/track.dart';

/// Ambiance déduite localement du tag « genre » d'un fichier.
class GenreMoodGuess {
  final MoodType mood;
  final double confidence;

  const GenreMoodGuess(this.mood, this.confidence);
}

class _GenreRule {
  final MoodType mood;
  final double confidence;
  final RegExp pattern;

  _GenreRule(this.mood, this.confidence, String source)
      : pattern = RegExp(source);
}

/// Pré-classe un morceau à partir de son tag genre, sans réseau.
///
/// Volontairement prudent : seuls les genres qui désignent sans ambiguïté
/// une ambiance (gospel, classique, métal, berceuse...) sont tranchés ici.
/// Les genres larges (pop, rock, rap, électro, R&B...) ne disent rien de
/// fiable sur l'ambiance : [guess] renvoie null et le morceau part chez
/// Groq. Idem si le genre correspond à plusieurs ambiances à la fois
/// (« Christian Metal »).
class GenreMoodClassifier {
  static final List<_GenreRule> _rules = [
    _GenreRule(
      MoodType.evangelical,
      0.85,
      r'\b(gospel|worship|louanges?|adoration|cantiques?|christian|'
      r'chretien(ne)?s?|praise|ccm|hymns?|hymnes?)\b',
    ),
    _GenreRule(
      MoodType.classical,
      0.8,
      r'\b(classical|neoclassical|orchestral|symphon(y|ic|ie)|baroque|'
      r'chamber music)\b|^(musique )?classique$',
    ),
    _GenreRule(
      MoodType.sleep,
      0.8,
      r'\b(lullab(y|ies)|berceuses?|sleep)\b',
    ),
    _GenreRule(
      MoodType.spiritual,
      0.8,
      r'\b(meditation|yoga|mantras?|tibetan|tibetain|mindfulness|kirtan)\b',
    ),
    _GenreRule(
      MoodType.angry,
      0.75,
      r'\b(metal(core)?|hardcore|grindcore|thrash|drill)\b',
    ),
    _GenreRule(
      MoodType.funny,
      0.8,
      r'\b(comedy|comedie|humou?r|parody|parodie|stand-?up|sketch)\b',
    ),
    _GenreRule(
      MoodType.concentration,
      0.75,
      r'\b(lo[- ]?fi|study|focus)\b',
    ),
    _GenreRule(
      MoodType.festive,
      0.7,
      r'\b(party|soiree|fete)\b',
    ),
    _GenreRule(
      MoodType.energetic,
      0.7,
      r'\b(workout|fitness|gym|cardio|running)\b',
    ),
    _GenreRule(
      MoodType.romantic,
      0.75,
      r'\b(romance|romantic|romantique|love songs?|slow jams?)\b',
    ),
    _GenreRule(
      MoodType.roadtrip,
      0.7,
      r'\b(road ?trip)\b',
    ),
  ];

  /// Minuscules, sans accents : les tags sont écrits à la main, dans
  /// n'importe quelle langue.
  static String normalize(String s) {
    const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in s.trim().toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i == -1 ? ch : to[i]);
    }
    return b.toString();
  }

  /// L'ambiance que dit clairement [genre], ou null si le genre est
  /// absent, trop large, ou ambigu.
  static GenreMoodGuess? guess(String? genre) {
    if (genre == null) return null;
    final g = normalize(genre);
    if (g.isEmpty) return null;

    final hits = <MoodType, double>{};
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(g)) hits[rule.mood] = rule.confidence;
    }
    if (hits.length != 1) return null;
    final entry = hits.entries.single;
    return GenreMoodGuess(entry.key, entry.value);
  }
}
