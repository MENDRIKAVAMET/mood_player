import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/track.dart';

/// Classifies tracks by mood using Groq's OpenAI-compatible chat
/// completions API. Chosen over Gemini for this task because it's a
/// lightweight text-only classification (title/artist -> one mood label),
/// where Groq's LPU inference is both much faster per call and has a far
/// more generous free daily request quota than Gemini's free tier -
/// important when classifying a whole library sequentially.
class GroqService {
  late final Dio _dio;
  final String _apiKey;

  /// Any current Groq-hosted instruction-following model works well for
  /// this simple JSON classification task.
  static const String _model = 'llama-3.3-70b-versatile';

  GroqService()
      : _apiKey = dotenv.isInitialized ? (dotenv.env['GROQ_API_KEY'] ?? '') : '' {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.groq.com/openai/v1',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
    ));
  }

  /// Classify a single track by mood using Groq
  Future<MoodClassificationResult> classifyTrack(Track track) async {
    final prompt = _buildClassificationPrompt(track);

    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.3,
          'max_tokens': 200,
          // Forces a valid JSON object back, no prose/markdown fences to strip.
          'response_format': {'type': 'json_object'},
        },
      );

      final content = response.data['choices'][0]['message']['content'] as String;
      return _parseClassificationResponse(content);
    } on DioException catch (e) {
      final serverMessage = e.response?.data is Map
          ? (e.response?.data['error']?['message'] ?? e.message)
          : e.message;
      throw GroqServiceException(
        'Erreur réseau lors de la classification: $serverMessage',
        e,
      );
    } catch (e) {
      throw GroqServiceException(
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
Tu es un expert en musique. Analyse le morceau suivant et détermine son ambiance (mood).

Titre: ${track.title}
Artiste: ${track.artist}
${track.album != null ? 'Album: ${track.album}' : ''}

Classe ce morceau dans l'une des catégories suivantes:
- énergique: musique dynamique, entraînante, parfaite pour le sport ou la danse
- chill: musique détendue, calme, parfaite pour se relaxer
- mélancolique: musique triste, nostalgique, émouvante
- festif: musique de fête, joyeuse, parfaite pour les célébrations
- romantique: musique d'amour, tendre, intime
- concentration: musique instrumentale, calme, parfaite pour travailler
- motivant: musique inspirante, qui donne envie d'avancer
- triste: musique très triste, mélancolique profonde

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
      throw GroqServiceException(
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

class GroqServiceException implements Exception {
  final String message;
  final dynamic originalError;

  const GroqServiceException(this.message, [this.originalError]);

  @override
  String toString() => 'GroqServiceException: $message';
}
