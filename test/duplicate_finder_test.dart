import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/duplicate_finder.dart';

Track _t(
  int id,
  String title,
  String artist,
  int? duration, {
  bool liked = false,
  MoodType? mood,
  String? path,
  DateTime? created,
}) =>
    Track()
      ..id = id
      ..title = title
      ..artist = artist
      ..duration = duration
      ..isLiked = liked
      ..mood = mood
      ..filePath = path
      ..createdAt = created;

void main() {
  test('normalisation : casse, accents, mentions parasites', () {
    expect(DuplicateFinder.normalizeTitle('Café (Official Video)'), 'cafe');
    expect(DuplicateFinder.normalizeTitle('01 - Ma Chanson [HD]'),
        'ma chanson');
    expect(DuplicateFinder.normalizeTitle('Song feat. Someone'), 'song');
    expect(DuplicateFinder.normalizeArtist('Unknown'), '');
  });

  test('détecte deux exemplaires du même morceau', () {
    final groups = DuplicateFinder.find([
      _t(1, 'Ma Chanson', 'Artiste', 200000),
      _t(2, 'ma chanson (Official Audio)', 'ARTISTE', 201000),
      _t(3, 'Autre', 'Artiste', 200000),
    ]);
    expect(groups.length, 1);
    expect(groups.first.tracks.map((t) => t.id).toSet(), {1, 2});
  });

  test('durées trop différentes : pas un doublon (live, remix)', () {
    final groups = DuplicateFinder.find([
      _t(1, 'Titre', 'Artiste', 200000),
      _t(2, 'Titre', 'Artiste', 260000),
    ]);
    expect(groups, isEmpty);
  });

  test('artistes différents : pas un doublon', () {
    final groups = DuplicateFinder.find([
      _t(1, 'Titre', 'Artiste A', 200000),
      _t(2, 'Titre', 'Artiste B', 200000),
    ]);
    expect(groups, isEmpty);
  });

  test('durée inconnue n\'est jamais mélangée à une durée connue', () {
    final groups = DuplicateFinder.find([
      _t(1, 'Titre', 'Artiste', 200000),
      _t(2, 'Titre', 'Artiste', null),
    ]);
    expect(groups, isEmpty);
  });

  test('exemplaire conseillé : favori > classé > dossier jetable > ancien', () {
    final groups = DuplicateFinder.find([
      _t(1, 'Titre', 'A', 200000,
          path: '/storage/emulated/0/Download/t.mp3',
          created: DateTime(2023)),
      _t(2, 'Titre', 'A', 200000,
          mood: MoodType.chill, created: DateTime(2024)),
      _t(3, 'Titre', 'A', 200000, liked: true, created: DateTime(2025)),
    ]);
    expect(groups.single.tracks.map((t) => t.id).toList(), [3, 2, 1]);
    expect(groups.single.suggestedKeeper.id, 3);
  });
}
