import 'package:isar/isar.dart';

part 'custom_mood.g.dart';

/// A user-created mood/playlist. Distinct from the built-in [MoodType]
/// (Groq's single automatic classification per track) - a track can belong
/// to any number of [CustomMood]s, each with its own match percentage for
/// that track, editable and sortable.
@collection
class CustomMood {
  Id id = Isar.autoIncrement;

  @Index()
  late String name;

  /// Clé d'icône Material (voir [MoodIcons]) — les moods créés avant ce
  /// changement peuvent encore contenir un glyphe emoji ; [MoodIcons]
  /// sait convertir les deux.
  String icon = 'music';

  /// ARGB color value used to theme the mood's cards/screen.
  int colorValue = 0xFF7C6CFF;

  /// Track IDs in this mood, in the order they were added.
  List<int> trackIds = [];

  /// Match percentage (0-100) for each track, index-aligned with
  /// [trackIds]. Kept as a parallel list (rather than a map, which Isar
  /// can't store directly) since both lists are always read/written
  /// together.
  List<double> trackPercentages = [];

  DateTime createdAt = DateTime.now();
  DateTime? updatedAt;

  @ignore
  int get trackCount => trackIds.length;

  /// Look up the stored percentage for a track, or null if it's not in
  /// this mood.
  double? percentageFor(int trackId) {
    final index = trackIds.indexOf(trackId);
    if (index == -1 || index >= trackPercentages.length) return null;
    return trackPercentages[index];
  }
}
