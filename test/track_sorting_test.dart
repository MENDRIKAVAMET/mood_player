import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/providers/track_provider.dart';
import 'package:mood_player/widgets/track_list_tools.dart';

Track _t(int id, String title, DateTime created) => Track()
  ..id = id
  ..title = title
  ..artist = 'A'
  ..createdAt = created;

void main() {
  final tracks = [
    _t(1, 'banane', DateTime(2024, 1, 2)),
    _t(2, 'Abricot', DateTime(2024, 1, 3)),
    _t(3, 'cerise', DateTime(2024, 1, 1)),
  ];

  List<int> ids(List<Track> l) => l.map((t) => t.id).toList();

  test('tri par nom, insensible à la casse', () {
    expect(ids(sortTracks(tracks, TrackSortOption.nameAsc)), [2, 1, 3]);
    expect(ids(sortTracks(tracks, TrackSortOption.nameDesc)), [3, 1, 2]);
  });

  test('tri par date', () {
    expect(ids(sortTracks(tracks, TrackSortOption.dateNewest)), [2, 1, 3]);
    expect(ids(sortTracks(tracks, TrackSortOption.dateOldest)), [3, 1, 2]);
  });

  test('ne modifie pas la liste d\'origine', () {
    sortTracks(tracks, TrackSortOption.nameAsc);
    expect(ids(tracks), [1, 2, 3]);
  });
}
