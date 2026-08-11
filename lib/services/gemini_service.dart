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