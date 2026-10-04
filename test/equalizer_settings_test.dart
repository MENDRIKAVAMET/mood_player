import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/equalizer_settings.dart';

void main() {
  test('resample garde les extrémités et interpole', () {
    final r = EqualizerSettings.resample([0, 10], 3);
    expect(r, [0, 5, 10]);
    expect(EqualizerSettings.resample([1, 2, 3], 3), [1, 2, 3]);
    expect(EqualizerSettings.resample([], 4), [0, 0, 0, 0]);
  });

  test('un préréglage s\'adapte au nombre de bandes', () {
    const s = EqualizerSettings(preset: 'Basses');
    expect(s.gainsFor(5), [6, 4, 0, 0, 0]);
    final g = s.gainsFor(4);
    expect(g.length, 4);
    expect(g.first, 6);
    expect(g.last, 0);
  });

  test('réglages personnalisés', () {
    const s = EqualizerSettings(
        preset: EqualizerSettings.customName, gains: [1, 2, 3, 4]);
    expect(s.gainsFor(4), [1, 2, 3, 4]);
  });

  test('aller-retour JSON', () {
    const s = EqualizerSettings(
        enabled: true, preset: 'Rock', gains: [1, 2], loudnessDb: 3);
    final back = EqualizerSettings.fromJson(s.toJson());
    expect(back.enabled, true);
    expect(back.preset, 'Rock');
    expect(back.loudnessDb, 3);
  });
}
