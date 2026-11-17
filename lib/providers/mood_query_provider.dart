import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/groq_service.dart';
import '../services/mood_query_parser.dart';
import 'track_provider.dart' show groqServiceProvider;

/// Comprend une recherche par ambiance en langage naturel : d'abord
/// localement (mots-clés, instantané, hors ligne), puis, sur demande
/// seulement, via Groq pour les formulations floues.
///
/// Groq n'est jamais appelé à la frappe : une requête réseau par lettre
/// serait lente et gaspillerait le quota. Les interprétations déjà obtenues
/// sont gardées en mémoire pour la session.
class MoodQueryService {
  final GroqService _groq;
  MoodQueryService(this._groq);

  final Map<String, MoodQuery> _aiCache = {};

  /// Interprétation locale (synchrone).
  MoodQuery parseLocal(String query) => MoodQueryParser.parse(query);

  /// Interprétation déjà obtenue de Groq pour [query], sans appel réseau.
  MoodQuery? cachedAi(String query) =>
      _aiCache[MoodQueryParser.normalize(query)];

  /// Demande à Groq. Peut lancer les exceptions de [GroqService].
  Future<MoodQuery> interpretWithAi(String query) async {
    final key = MoodQueryParser.normalize(query);
    if (key.isEmpty) return MoodQuery.empty;
    final cached = _aiCache[key];
    if (cached != null) return cached;

    final r = await _groq.interpretMoodQuery(query);
    final result = MoodQuery(
      weights: r.weights,
      excluded: r.excluded,
      fromAi: true,
    );
    // On ne mémorise que les succès : un « rien compris » peut venir d'un
    // raté passager et ne doit pas bloquer un nouvel essai.
    if (result.hasMoods || result.hasExclusions) _aiCache[key] = result;
    return result;
  }
}

final moodQueryServiceProvider = Provider<MoodQueryService>((ref) {
  return MoodQueryService(ref.watch(groqServiceProvider));
});
