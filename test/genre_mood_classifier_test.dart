import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/genre_mood_classifier.dart';
import 'package:mood_player/services/groq_service.dart';
import 'package:mood_player/services/mood_correction_service.dart';

Track _track(String title, String artist, {String? path}) => Track()
  ..title = title
  ..artist = artist
  ..filePath = path;

void main() {
  group('GenreMoodClassifier', () {
    test('tranche les genres sans ambiguïté', () {
      expect(GenreMoodClassifier.guess('Gospel')?.mood, MoodType.evangelical);
      expect(GenreMoodClassifier.guess('Louange & Adoration')?.mood,
          MoodType.evangelical);
      expect(GenreMoodClassifier.guess('Classical')?.mood, MoodType.classical);
      expect(GenreMoodClassifier.guess('Musique classique')?.mood,
          MoodType.classical);
      expect(GenreMoodClassifier.guess('Heavy Metal')?.mood, MoodType.angry);
      expect(GenreMoodClassifier.guess('Berceuse')?.mood, MoodType.sleep);
      expect(GenreMoodClassifier.guess('Lo-Fi')?.mood, MoodType.concentration);
      expect(GenreMoodClassifier.guess('Méditation')?.mood, MoodType.spiritual);
    });

    test('laisse à Groq les genres larges ou absents', () {
      for (final g in ['Pop', 'Rock', 'Hip-Hop', 'Rap', 'Electronic', 'R&B',
          'Other', 'Soundtrack', '(17)', '', '   ']) {
        expect(GenreMoodClassifier.guess(g), isNull, reason: g);
      }
      expect(GenreMoodClassifier.guess(null), isNull);
    });

    test('ne confond pas « Classic Rock » ni « Christmas »', () {
      expect(GenreMoodClassifier.guess('Classic Rock'), isNull);
      expect(GenreMoodClassifier.guess('Christmas'), isNull);
    });

    test('genre ambigu (plusieurs ambiances) : pas de décision locale', () {
      expect(GenreMoodClassifier.guess('Christian Metal'), isNull);
    });
  });

  group('indice de genre et corrections', () {
    late Directory tmp;
    late MoodCorrectionService service;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('genre_corr');
      service = MoodCorrectionService(
        fileOverride: () async => File('${tmp.path}/c.json'),
      );
    });

    tearDown(() async => tmp.delete(recursive: true));

    test('le prompt Groq indique le genre des morceaux qui en ont un', () {
      final t = _track('Titre', 'Artiste', path: '/m/a.mp3');
      final prompt = GroqService()
          .buildBatchPromptForTest([t], const [], {'/m/a.mp3': 'Afrobeats'});
      expect(prompt, contains('| Genre: Afrobeats'));
      expect(prompt, contains('indice utile'));
    });

    test('sans genre, le prompt reste inchangé', () {
      final prompt = GroqService()
          .buildBatchPromptForTest([_track('A', 'B', path: '/m/a.mp3')], const []);
      expect(prompt, isNot(contains('Genre:')));
    });

    test('un genre déjà contredit par l\'utilisateur devient « contesté »',
        () async {
      await service.record(_track('Slow', 'X'), MoodType.chill, genre: 'Gospel');

      expect(await service.isContested('gospel', MoodType.evangelical), isTrue);
      expect(await service.isContested('Gospel', MoodType.chill), isFalse);
      expect(await service.isContested('Classical', MoodType.classical), isFalse);
    });
  });
}
