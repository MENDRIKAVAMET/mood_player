import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/backup_service.dart';

Track _track(int id, String title, String artist, {int? duration}) => Track()
  ..id = id
  ..title = title
  ..artist = artist
  ..duration = duration;

void main() {
  group('BackupService.trackKey', () {
    test('ignore casse, accents et ponctuation', () {
      expect(
        BackupService.trackKey('Déjà Vu!', 'Beyoncé'),
        BackupService.trackKey('deja vu', 'BEYONCE'),
      );
    });

    test('distingue deux titres différents', () {
      expect(
        BackupService.trackKey('Song A', 'X'),
        isNot(BackupService.trackKey('Song B', 'X')),
      );
    });
  });

  group('BackupService.matchTracks', () {
    test('retrouve un morceau malgré un id différent', () {
      final backup = [
        const BackupTrack(ref: 7, title: 'Hello', artist: 'Adele', durationMs: 295000),
      ];
      final local = [_track(1, 'hello', 'ADELE', duration: 295400)];
      final m = BackupService.matchTracks(backup, local);
      expect(m[7]?.id, 1);
    });

    test('refuse une version de durée très différente', () {
      final backup = [
        const BackupTrack(ref: 1, title: 'Hello', artist: 'Adele', durationMs: 295000),
      ];
      final local = [_track(1, 'Hello', 'Adele', duration: 420000)];
      expect(BackupService.matchTracks(backup, local), isEmpty);
    });

    test('un morceau local ne sert qu\'une fois', () {
      final backup = [
        const BackupTrack(ref: 1, title: 'A', artist: 'B'),
        const BackupTrack(ref: 2, title: 'A', artist: 'B'),
      ];
      final local = [_track(10, 'A', 'B')];
      expect(BackupService.matchTracks(backup, local).length, 1);
    });

    test('doublons : prend la durée la plus proche', () {
      final backup = [
        const BackupTrack(ref: 1, title: 'A', artist: 'B', durationMs: 200000),
      ];
      final local = [
        _track(10, 'A', 'B', duration: 203000),
        _track(11, 'A', 'B', duration: 200500),
      ];
      expect(BackupService.matchTracks(backup, local)[1]?.id, 11);
    });
  });

  group('BackupService.parse', () {
    test('aller-retour JSON', () {
      final data = BackupData(
        exportedAt: DateTime.utc(2026, 10, 3),
        tracks: const [
          BackupTrack(ref: 1, title: 'T', artist: 'A', mood: 'chill', moodConfidence: 0.8),
        ],
        likedRefs: {1},
        playCounts: {1: 3},
        customMoods: const [
          BackupCustomMood(name: 'Route', icon: 'car', colorValue: 1, entries: {1: 90}),
        ],
        favoriteArtists: const ['A'],
        periodMoods: const {'morning': ['chill']},
        smartQueueEnabled: true,
      );
      final back = BackupService.parse(jsonEncode(data.toJson()));
      expect(back.tracks.single.moodType, MoodType.chill);
      expect(back.classifiedCount, 1);
      expect(back.likedRefs, {1});
      expect(back.playCounts, {1: 3});
      expect(back.customMoods.single.entries, {1: 90.0});
      expect(back.favoriteArtists, ['A']);
      expect(back.periodMoods['morning'], ['chill']);
      expect(back.smartQueueEnabled, true);
    });

    test('rejette un JSON quelconque', () {
      expect(() => BackupService.parse('{"a":1}'),
          throwsA(isA<BackupFormatException>()));
      expect(() => BackupService.parse('pas du json'),
          throwsA(isA<BackupFormatException>()));
    });

    test('rejette une version plus récente', () {
      expect(
        () => BackupService.parse('{"app":"mood_player","version":99}'),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });
}
