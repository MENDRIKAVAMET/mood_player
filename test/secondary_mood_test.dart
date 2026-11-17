import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/backup_service.dart';
import 'package:mood_player/services/groq_service.dart';
import 'package:mood_player/services/track_secondary_mood_store.dart';

Track _track(String title, {String? path, MoodType? mood, MoodType? second}) =>
    Track()
      ..title = title
      ..artist = 'Artiste'
      ..filePath = path
      ..mood = mood
      ..secondaryMood = second;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('secondary_mood');
    TrackSecondaryMoods.fileOverride = () async => File('${tmp.path}/s.json');
    TrackSecondaryMoods.resetCache();
  });

  tearDown(() async {
    TrackSecondaryMoods.fileOverride = null;
    TrackSecondaryMoods.resetCache();
    await tmp.delete(recursive: true);
  });

  group('Track', () {
    test('la secondaire identique à la principale est ignorée', () {
      final t = _track('a', mood: MoodType.chill, second: MoodType.chill);
      expect(t.effectiveSecondaryMood, isNull);
    });

    test('hasMood regarde la principale et la secondaire', () {
      final t = _track('a', mood: MoodType.chill, second: MoodType.nostalgic);
      expect(t.hasMood(MoodType.chill), isTrue);
      expect(t.hasMood(MoodType.nostalgic), isTrue);
      expect(t.hasMood(MoodType.dark), isFalse);
    });
  });

  group('TrackSecondaryMoods', () {
    test('persiste, recharge et retire', () async {
      await TrackSecondaryMoods.set('/m/a.mp3', MoodType.nostalgic);
      TrackSecondaryMoods.resetCache();

      final t = _track('a', path: '/m/a.mp3', mood: MoodType.chill);
      await TrackSecondaryMoods.applyTo([t]);
      expect(t.secondaryMood, MoodType.nostalgic);

      await TrackSecondaryMoods.set('/m/a.mp3', null);
      TrackSecondaryMoods.resetCache();
      await TrackSecondaryMoods.applyTo([t]);
      expect(t.secondaryMood, isNull);
    });

    test('suit un renommage de fichier', () async {
      await TrackSecondaryMoods.set('/m/old.mp3', MoodType.dark);
      await TrackSecondaryMoods.move('/m/old.mp3', '/m/new.mp3');
      final map = await TrackSecondaryMoods.load();
      expect(map.containsKey('/m/old.mp3'), isFalse);
      expect(map['/m/new.mp3'], MoodType.dark);
    });

    test('ignore un fichier corrompu', () async {
      await File('${tmp.path}/s.json').writeAsString('{pas du json');
      expect(await TrackSecondaryMoods.load(), isEmpty);
    });
  });

  group('Groq', () {
    test('le prompt demande une ambiance secondaire', () {
      final prompt =
          GroqService().buildBatchPromptForTest([_track('Song')], const []);
      expect(prompt, contains('AMBIANCE SECONDAIRE'));
      expect(prompt, contains('mood2'));
    });
  });

  group('Groq parsing', () {
    final chunk = [_track('A'), _track('B'), _track('C')];
    final res = GroqService().parseBatchResponseForTest(
      '{"classifications": ['
      '{"id": 0, "mood": "chill", "mood2": "nostalgique", "confiance": 0.8},'
      '{"id": 1, "mood": "chill", "mood2": "chill", "confiance": 0.8},'
      '{"id": 2, "mood": "festif", "mood2": null, "confiance": 0.7}]}',
      chunk,
    );

    test('lit la secondaire valide', () {
      expect(res[0].mood, MoodType.chill);
      expect(res[0].secondaryMood, MoodType.nostalgic);
    });

    test('ignore une secondaire identique à la principale', () {
      expect(res[1].secondaryMood, isNull);
    });

    test('null = pas de nuance', () {
      expect(res[2].mood, MoodType.festive);
      expect(res[2].secondaryMood, isNull);
    });
  });

  group('Sauvegarde', () {
    test('mood2 fait l\'aller-retour, et est optionnel', () {
      const withSecond = BackupTrack(
        ref: 1,
        title: 'T',
        artist: 'A',
        mood: 'chill',
        secondaryMood: 'nostalgic',
      );
      final back = BackupTrack.fromJson(withSecond.toJson());
      expect(back.secondaryMoodType, MoodType.nostalgic);

      final old = BackupTrack.fromJson({'ref': 2, 'title': 'T', 'artist': 'A'});
      expect(old.secondaryMoodType, isNull);
    });
  });
}
