import 'package:isar/isar.dart';

part 'playlist.g.dart';

@collection
class Playlist {
  Id id = Isar.autoIncrement;

  @Index()
  late String name;

  String? description;

  /// List of track IDs in order
  late List<int> trackIds;

  DateTime? createdAt;

  DateTime? updatedAt;

  /// Get the number of tracks
  int get trackCount => trackIds.length;

  @ignore
  bool get isEmpty => trackIds.isEmpty;

  @ignore
  bool get isNotEmpty => trackIds.isNotEmpty;
}
