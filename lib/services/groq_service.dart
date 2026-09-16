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
  static const String _model = 'qwen/qwen3.6-27b';

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

  /// Maximum tracks sent in a single classification request. Kept well
  /// under the model's context/output limits while still cutting request
  /// count by ~50x compared to one call per track.
  static const int maxBatchSize = 50;

  /// Classify a single track (implemented as a batch of one, so parsing
  /// logic only lives in one place).
  Future<MoodClassificationResult> classifyTrack(Track track) async {
    final results = await classifyTracksBatch([track]);
    return results.first;
  }

  /// Classify many tracks in as few requests as possible: splits [tracks]
  /// into chunks of [maxBatchSize] and sends one request per chunk, asking
  /// the model to return a mood for every track in that chunk in a single
  /// JSON response. Results are returned in the same order as [tracks].
  Future<List<MoodClassificationResult>> classifyTracksBatch(List<Track> tracks) async {
    if (tracks.isEmpty) return [];

    final results = <MoodClassificationResult>[];
    for (var start = 0; start < tracks.length; start += maxBatchSize) {
      final chunk = tracks.sublist(
        start,
        (start + maxBatchSize).clamp(0, tracks.length),
      );
      results.addAll(await _classifyChunk(chunk));
    }
    return results;
  }

  /// Sends exactly one request classifying every track in [chunk].
  Future<List<MoodClassificationResult>> _classifyChunk(List<Track> chunk) async {
    final prompt = _buildBatchPrompt(chunk);

    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.3,
          // Each result is a short JSON object; scale the budget with the
          // batch size so large batches don't get truncated mid-response.
          'max_tokens': 60 * chunk.length + 200,
          // Forces a valid JSON object back, no prose/markdown fences to strip.
          'response_format': {'type': 'json_object'},
        },
      );

      final content = response.data['choices'][0]['message']['content'] as String;
      return _parseBatchResponse(content, chunk);
    } on DioException catch (e) {
      final serverMessage = e.response?.data is Map
          ? (e.response?.data['error']?['message'] ?? e.message)
          : e.message;

      if (e.response?.statusCode == 429) {
        throw GroqRateLimitException(
          'Limite de requêtes Groq atteinte: $serverMessage',
          retryAfter: _parseRetryAfter(e.response?.headers),
          originalError: e,
        );
      }

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

  /// Reads the standard `Retry-After` header (seconds) Groq sends on 429
  /// responses. Falls back to a conservative default if absent/unparsable.
  Duration _parseRetryAfter(Headers? headers) {
    final raw = headers?.value('retry-after');
    final seconds = raw != null ? int.tryParse(raw) : null;
    return Duration(seconds: seconds ?? 20);
  }

  String _buildBatchPrompt(List<Track> chunk) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Tu es un expert en musique. Voici une liste de ${chunk.length} morceaux, '
      'chacun avec un identifiant numérique. Détermine l\'ambiance (mood) de '
      'CHAQUE morceau.',
    );
    buffer.writeln();
    buffer.writeln('Catégories possibles (utilise exactement ces mots):');
    buffer.writeln('- énergique: dynamique, entraînant, sport/danse');
    buffer.writeln('- chill: détendu, calme, relaxant');
    buffer.writeln('- mélancolique: triste, nostalgique, émouvant');
    buffer.writeln('- festif: fête, joyeux, célébration');
    buffer.writeln('- romantique: amour, tendre, intime');
    buffer.writeln('- concentration: instrumental, calme, travail');
    buffer.writeln('- motivant: inspirant, donne envie d\'avancer');
    buffer.writeln('- triste: très triste, mélancolie profonde');
    buffer.writeln();
    buffer.writeln('Morceaux à classer:');
    for (var i = 0; i < chunk.length; i++) {
      final t = chunk[i];
      final album = t.album != null && t.album!.isNotEmpty ? ' | Album: ${t.album}' : '';
      buffer.writeln('$i. Titre: ${t.title} | Artiste: ${t.artist}$album');
    }
    buffer.writeln();
    buffer.writeln(
      'Réponds UNIQUEMENT avec un JSON valide au format suivant, avec EXACTEMENT '
      '${chunk.length} entrées dans "classifications", une par morceau, dans le '
      'même ordre, en reprenant le numéro d\'identifiant donné ci-dessus:',
    );
    buffer.writeln(
      '{"classifications": [{"id": 0, "mood": "catégorie", "confiance": 0.0-1.0}, ...]}',
    );
    return buffer.toString();
  }

  /// Parses a batch response and returns one result per track in [chunk],
  /// in the same order - falling back to an error entry for any track the
  /// model didn't return a matching id for.
  List<MoodClassificationResult> _parseBatchResponse(String response, List<Track> chunk) {
    Map<int, dynamic> byId = {};

    try {
      String jsonStr = response.trim();
      final jsonStart = jsonStr.indexOf('{');
      final jsonEnd = jsonStr.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        jsonStr = jsonStr.substring(jsonStart, jsonEnd + 1);
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final list = json['classifications'] as List<dynamic>? ?? [];

      for (final entry in list) {
        if (entry is Map<String, dynamic>) {
          final id = (entry['id'] as num?)?.toInt();
          if (id != null) byId[id] = entry;
        }
      }
    } catch (e) {
      throw GroqServiceException(
        'Erreur lors de l\'analyse de la réponse JSON du lot: $e',
        e,
      );
    }

    return List.generate(chunk.length, (i) {
      final entry = byId[i];
      if (entry == null) {
        return MoodClassificationResult(
          trackId: chunk[i].id,
          mood: MoodType.unknown,
          confidence: 0.0,
          error: 'Aucune classification retournée par Groq pour ce morceau',
        );
      }

      final moodString = entry['mood'] as String? ?? 'unknown';
      final confidence = (entry['confiance'] as num?)?.toDouble() ?? 0.0;

      return MoodClassificationResult(
        trackId: chunk[i].id,
        mood: MoodTypeExtension.fromString(moodString),
        confidence: confidence.clamp(0.0, 1.0),
      );
    });
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

/// Thrown when Groq responds with HTTP 429 (rate limit exceeded). Carries
/// how long to wait before it's safe to retry.
class GroqRateLimitException extends GroqServiceException {
  final Duration retryAfter;

  const GroqRateLimitException(
    String message, {
    required this.retryAfter,
    dynamic originalError,
  }) : super(message, originalError);
}
