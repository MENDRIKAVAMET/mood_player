import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/equalizer_settings.dart';
import 'package:mood_player/services/loudness_service.dart';

void main() {
  test('un morceau trop fort est atténué, un morceau calme est renforcé', () {
    expect(LoudnessService.gainFor(-8), -6);
    expect(LoudnessService.gainFor(-18), 4);
    expect(LoudnessService.gainFor(-14), 0);
  });

  test('les gains sont bornés', () {
    expect(LoudnessService.gainFor(0), LoudnessService.minGainDb);
    expect(LoudnessService.gainFor(-40), LoudnessService.maxGainDb);
  });

  test('clé de mémorisation : chemin, sinon URI', () {
    expect(LoudnessService.keyFor('/a.mp3', 'content://x'), '/a.mp3');
    expect(LoudnessService.keyFor(null, 'content://x'), 'content://x');
    expect(LoudnessService.keyFor('', null), null);
  });

  test('le réglage « volume uniforme » est sauvegardé', () {
    const s = EqualizerSettings(normalizeVolume: true);
    expect(EqualizerSettings.fromJson(s.toJson()).normalizeVolume, true);
    expect(EqualizerSettings.fromJson({}).normalizeVolume, false);
  });
}
