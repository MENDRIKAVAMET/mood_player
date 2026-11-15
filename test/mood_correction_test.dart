import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/groq_service.dart';
import 'package:mood_player/services/mood_correction_service.dart';

Track _track(String title, String artist, {String? album}) => Track()
  ..title = title
  ..artist = artist
  ..album = album;

void main() {
  late Directory tmp;
  late MoodCorrectionService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mood_corr');
    service = MoodCorrectionService(
      fileOverride: () async => File('${tmp.path}/c.json'),
    );
  });

  tearDown(() async => tmp.delete(recursive: true));

  test('enregistre, remplace et persiste une correction', () async {
    final t = _track('Song', 'Artist');
    await service.record(t, MoodType.chill);
    await service.record(t, MoodType.sleep);

    final reloaded = MoodCorrectionService(
      fileOverride: () async => File('${tmp.path}/c.json'),
    );
    final all = await reloaded.getAll();
    expect(all, hasLength(1));
    expect(all.single.mood, MoodType.sleep);
  });

  test('privilégie les mêmes artistes et plafonne par ambiance', () async {
    for (var i = 0; i < 8; i++) {
      await service.record(_track('Autre $i', 'Quelqu\'un'), MoodType.chill);
    }
    await service.record(_track('Ancien', 'Burna'), MoodType.energetic);

    final ex = await service.examplesFor([_track('Nouveau', 'Burna')]);
    expect(ex.first.artist, 'Burna');
    expect(
      ex.where((c) => c.mood == MoodType.chill).length,
      MoodCorrectionService.maxPerMood,
    );
  });

  test('le prompt Groq contient les corrections, nettoyées', () async {
    await service.record(
      _track('Slow\nJam "x"', 'Dj', album: 'Alb'),
      MoodType.chill,
    );
    final ex = await service.examplesFor([_track('Autre', 'Z')]);
    final prompt = GroqService().buildBatchPromptForTest([_track('Autre', 'Z')], ex);

    expect(prompt, contains('PRÉFÉRENCES PERSONNELLES'));
    expect(prompt, contains('Titre: Slow Jam x | Artiste: Dj | Album: Alb => chill'));
  });

  test('sans correction, le prompt ne change pas', () {
    final prompt = GroqService().buildBatchPromptForTest([_track('A', 'B')], const []);
    expect(prompt, isNot(contains('PRÉFÉRENCES PERSONNELLES')));
  });
}
