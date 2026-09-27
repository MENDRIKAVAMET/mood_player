import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/track.dart';

class GeminiService {
  late final Dio _dio;
  final String _apiKey;

  GeminiService()
      : _apiKey = dotenv.isInitialized ? (dotenv.env['GEMINI_API_KEY'] ?? '') : '' {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  /// Classify a single track by mood using Gemini API
  Future<MoodClassificationResult> classifyTrack(Track track) async {
    final prompt = _buildClassificationPrompt(track);
    
    try {
      final response = await _dio.post(
        '/models/gemini-2.0-flash:generateContent?key=$_apiKey',
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.3,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 1024,
          }
        },
      );

      final content = response.data['candidates'][0]['content']['parts'][0]['text'];
      return _parseClassificationResponse(content);
    } on DioException catch (e) {
      throw GeminiServiceException(
        'Erreur réseau lors de la classification: ${e.message}',
        e,
      );
    } catch (e) {
      throw GeminiServiceException(
        'Erreur inattendue lors de la classification: $e',
        e,
      );
    }
  }

  /// Classify multiple tracks in batch
  Future<List<MoodClassificationResult>> classifyTracksBatch(List<Track> tracks) async {
    final results = <MoodClassificationResult>[];
    
    for (final track in tracks) {
      try {
        final result = await classifyTrack(track);
        results.add(result);
      } catch (e) {
        results.add(MoodClassificationResult(
          trackId: track.id,
          mood: MoodType.unknown,
          confidence: 0.0,
          error: e.toString(),
        ));
      }
    }
    
    return results;
  }

  String _buildClassificationPrompt(Track track) {
    return '''
Tu es un expert en musique, spécialisé dans la classification fine par ambiance (mood). Analyse le morceau suivant à partir de son titre, son artiste et son album - et de ta connaissance du morceau ou de l'artiste si tu le reconnais (genre musical, tempo habituel, thématique des paroles).

Titre: ${track.title}
Artiste: ${track.artist}
${track.album != null ? 'Album: ${track.album}' : ''}

Classe ce morceau dans l'une des catégories suivantes (une seule, la plus spécifique et la plus probable) :
- énergique: tempo rapide, dynamique, entraînant, pensé pour le sport, la danse ou l'effort physique
- chill: tempo modéré à lent, détendu, apaisant, ambiance légère sans être triste ni instrumentale de travail
- mélancolique: nostalgique, doux-amer, émouvant, sans être aussi sombre ou lourd que "triste"
- festif: pensé pour une fête, une soirée, une célébration collective (anniversaire, mariage, nouvel an)
- romantique: amour, séduction, tendresse, intimité à deux - distinct de "festif" et de "mélancolique"
- concentration: instrumental ou peu présent au chant, calme et régulier, pensé pour travailler/étudier plutôt que pour se détendre
- motivant: inspirant, donne envie d'avancer ou de se dépasser (ambition, victoire, énergie positive) - réservé à la musique profane ; ne s'applique jamais à un morceau évangélique/gospel, même si les paroles parlent de force ou de victoire
- triste: chagrin marqué, mélancolie profonde, morceau pensé pour accompagner un moment difficile
- évangélique: musique chrétienne / gospel / louange / adoration / worship / cantiques d'église, quel que soit son tempo ou son ambiance sonore (une louange rythmée et festive reste "évangélique", pas "festif" ni "énergique" ; une louange lente et priante reste "évangélique", pas "chill" ni "mélancolique"). Priorise cette catégorie dès qu'il y a un signal clair : artiste identifié comme gospel/louange, thématique religieuse explicite (Dieu, Jésus, l'Éternel, adoration, prière), ou album/titre en ce sens.

En cas d'hésitation entre deux catégories, préfère celle qui décrit le mieux l'intention d'écoute (pourquoi on mettrait ce morceau) plutôt que celle qui décrit juste le tempo.

Réponds UNIQUEMENT avec un JSON valide au format suivant:
{"mood": "catégorie", "confiance": 0.0-1.0}

Où "confiance" est un nombre entre 0 et 1 indiquant ton niveau de certitude.
''';
  }

  MoodClassificationResult _parseClassificationResponse(String response) {
    try {
      // Clean the response to extract JSON
      String jsonStr = response.trim();
      
      // Try to find JSON in the response
      final jsonStart = jsonStr.indexOf('{');
      final jsonEnd = jsonStr.lastIndexOf('}');
      
      if (jsonStart != -1 && jsonEnd != -1) {
        jsonStr = jsonStr.substring(jsonStart, jsonEnd + 1);
      }
      
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      final moodString = json['mood'] as String? ?? 'unknown';
      final confidence = (json['confiance'] as num?)?.toDouble() ?? 0.0;
      
      final mood = MoodTypeExtension.fromString(moodString);
      
      return MoodClassificationResult(
        mood: mood,
        confidence: confidence.clamp(0.0, 1.0),
      );
    } catch (e) {
      throw GeminiServiceException(
        'Erreur lors de l\'analyse de la réponse JSON: $e',
        e,
      );
    }
  }
}

class MoodClassificationResult {
  final int? trackId;
  final MoodType mood;
  final double confidence;
  final String? error;

  const MoodClassificationResult({
    this.trackId,
    required this.mood,
    required this.confidence,
    this.error,
  });

  bool get hasError => error != null;
}

class GeminiServiceException implements Exception {
  final String message;
  final dynamic originalError;

  const GeminiServiceException(this.message, [this.originalError]);

  @override
  String toString() => 'GeminiServiceException: $message';
}